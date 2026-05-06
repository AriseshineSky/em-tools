# frozen_string_literal: true

module Em
  module Tools
    module Amazon
      # Ruby counterpart to +em_tasks.applications.tools.amazon.uploadable_product_filter+ (phase 1).
      #
      # Resolves ASIN stream options like the Python +asin_stream_options+ module, builds an Elasticsearch
      # bool query (time range + optional label term), and streams matching ASINs from +amz_asins_<mp>+
      # (or +--index+ override) using a point-in-time search.
      #
      # Full Python pipeline (offers, price rules, rule engine, metrics index) is not ported yet; use this
      # for ASIN extraction / parity with CLI flags, or extend this class.
      class UploadableProductFilter
        attr_reader :marketplace, :asin_index, :ttl, :stream_opts

        def initialize(**opts)
          @marketplace = normalize_marketplace(opts.fetch(:marketplace))
          @asin_index = normalize_index(opts[:index], @marketplace)
          @ttl = opts.fetch(:ttl, 30).to_i
          @config = normalize_config(opts[:config])
          @stream_opts = stream_opts_from_cli(opts)
        end

        def resolved_time_field
          AsinStreamOptions.effective_time_field(@stream_opts[:time_field], @asin_index)
        end

        def cutoff_time_utc
          c = @stream_opts[:cutoff]
          return c if c

          days = @stream_opts[:relative_days].to_i
          days = 1 if days < 1
          Time.now.utc - (days * 86_400)
        end

        def asin_query
          field = resolved_time_field
          must = []
          must << { range: { field => { gt: cutoff_time_utc.iso8601(3) } } }
          lab = @stream_opts[:label]
          if lab && !lab.to_s.strip.empty?
            lf = @stream_opts[:label_field].to_s
            must << { term: { lf => lab } }
          end
          { bool: { must: must } }
        end

        def stream_asins!(client:, io: $stdout, max_asins: nil)
          each_asin_hit(client: client, max_hits: max_asins, batch_size: 500) do |hit|
            asin = extract_asin(hit)
            io.puts(asin) unless asin.empty?
          end
        end

        # Yields each hit from the ASIN index stream (same query as +stream_asins!+).
        def each_asin_hit(client:, max_hits: nil, batch_size: 500, &block)
          client.iterate_query(
            index: @asin_index,
            query: asin_query,
            batch_size: batch_size,
            max_hits: max_hits,
            &block
          )
        end

        def describe
          {
            marketplace: @marketplace,
            asin_index: @asin_index,
            ttl: @ttl,
            time_field: resolved_time_field,
            cutoff: cutoff_time_utc.iso8601(3),
            label: @stream_opts[:label],
            label_field: @stream_opts[:label_field],
            relative_days: @stream_opts[:relative_days]
          }
        end

        private

        def normalize_marketplace(value)
          mp = value.to_s.downcase.strip
          raise ArgumentError, 'marketplace is required' if mp.empty?

          mp
        end

        def normalize_index(idx, marketplace)
          return idx.to_s.strip if idx && !idx.to_s.strip.empty?

          "amz_asins_#{marketplace}"
        end

        def normalize_config(cfg)
          cfg.is_a?(Hash) ? cfg : {}
        end

        def stream_opts_from_cli(opts)
          AsinStreamOptions.resolve(
            @config,
            cli_since_days: opts.fetch(:asin_since_days, 7),
            cli_time_field: opts[:asin_time_field],
            cli_cutoff: opts[:asin_cutoff],
            cli_label: opts[:asin_label],
            cli_label_field: opts[:asin_label_field]
          )
        end

        def extract_asin(hit)
          src = hit['_source'] || {}
          (src['asin'] || hit['_id']).to_s.strip
        end
      end
    end
  end
end
