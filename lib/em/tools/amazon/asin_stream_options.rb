# frozen_string_literal: true

require 'time'

module Em
  module Tools
    module Amazon
      # Ruby port of +em_tasks/applications/tools/amazon/asin_stream_options.py+ (+resolve_asin_stream_options+).
      module AsinStreamOptions
        CFG_BLOCK_KEY = 'amz.uploadable_filter.asin_stream'
        FLAT_TIME_FIELD = 'amz.uploadable_filter.asin_stream_time_field'
        FLAT_CUTOFF = 'amz.uploadable_filter.asin_stream_cutoff'
        FLAT_LABEL = 'amz.uploadable_filter.asin_stream_label'
        FLAT_LABEL_FIELD = 'amz.uploadable_filter.asin_stream_label_field'

        class << self
          # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/ParameterLists
          def resolve(cfg, cli_since_days:, cli_time_field: nil, cli_cutoff: nil, cli_label: nil, cli_label_field: nil)
            cfg ||= {}
            time_field = 'auto'
            cutoff_raw = nil
            label = nil
            label_field = 'label'

            blk = cfg[CFG_BLOCK_KEY]
            if blk.is_a?(Hash)
              time_field = blk['time_field'].to_s.strip.downcase if blk['time_field']
              cutoff_raw = blk['cutoff'] if blk.key?('cutoff')
              label = strip_or_nil(blk['label']) if blk.key?('label')
              label_field = normalize_label_field(blk['label_field']) if blk.key?('label_field')
            end

            time_field = cfg[FLAT_TIME_FIELD].to_s.strip.downcase if cfg[FLAT_TIME_FIELD]
            cutoff_raw = cfg[FLAT_CUTOFF] if cfg.key?(FLAT_CUTOFF)
            label = strip_or_nil(cfg[FLAT_LABEL]) if cfg.key?(FLAT_LABEL)
            label_field = normalize_label_field(cfg[FLAT_LABEL_FIELD]) if cfg[FLAT_LABEL_FIELD]

            time_field = cli_time_field.to_s.strip.downcase if cli_time_field && !cli_time_field.to_s.strip.empty?
            cutoff_raw = cli_cutoff if cli_cutoff && !cli_cutoff.to_s.strip.empty?
            label = strip_or_nil(cli_label) unless cli_label.nil?
            label_field = normalize_label_field(cli_label_field) if cli_label_field

            unless %w[auto timestamp created_at time].include?(time_field)
              raise ArgumentError,
                    "asin_stream time_field must be auto|timestamp|created_at|time; got #{time_field.inspect}"
            end

            cutoff_dt =
              if cutoff_raw.nil? || cutoff_raw.to_s.strip.empty?
                nil
              else
                parse_iso8601_utc(cutoff_raw)
              end

            {
              time_field: time_field,
              cutoff: cutoff_dt,
              label: label,
              label_field: label_field,
              relative_days: cli_since_days.to_i
            }
          end
          # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity, Metrics/ParameterLists

          def effective_time_field(time_field, asin_index)
            tf = time_field.to_s.strip.downcase
            return tf unless tf == 'auto'

            asin_index.to_s.include?('keyword') ? 'time' : 'timestamp'
          end

          def strip_or_nil(value)
            return nil if value.nil?

            s = value.to_s.strip
            s.empty? ? nil : s
          end

          def normalize_label_field(value)
            lf = value.to_s.strip
            lf.empty? ? 'label' : lf
          end

          def parse_iso8601_utc(raw)
            s = raw.to_s.strip
            raise ArgumentError, "invalid ISO8601: #{raw.inspect}" if s.empty?

            Time.iso8601(s).utc
          rescue StandardError => e
            raise ArgumentError, "invalid ISO8601: #{raw.inspect} (#{e.message})"
          end
        end
      end
    end
  end
end
