# frozen_string_literal: true

module EmTools
  module Core
    # Generic record-level pipeline driver: filters -> transforms -> sink.
    #
    # A plugin (or the caller) supplies the source/sink; the engine pulls each record from
    # +source+, applies every filter (all must pass), folds it through the transforms, and hands
    # the result to +sink#index+. Optional +flush!+ on the sink runs at the end of #run.
    #
    # Plugins whose existing logic is too coarse to fit this per-record contract (e.g. coverage
    # snapshot queries, bulk filter+ingest pipelines) keep their own ad-hoc operations and do not
    # have to use this engine. Use it for new, simple, per-record streams.
    class PipelineEngine
      def initialize(plugin, source: nil, sink: nil, **source_opts)
        @plugin = plugin
        @filters = Array(plugin.filters)
        @transforms = Array(plugin.transforms)
        @source = source || plugin.source(**source_opts)
        @sink = sink || plugin.sink(**source_opts)
      end

      # Pull every record from the source, run it through the chain, and flush the sink.
      def run
        unless @source.respond_to?(:each)
          raise ArgumentError,
            "PipelineEngine#run requires a source responding to #each"
        end

        @source.each { |record| call(record) }
        @sink.flush! if @sink.respond_to?(:flush!)
        nil
      end

      # Run a single record through filters + transforms + sink.
      # Returns the transformed record, or +nil+ if it was filtered out.
      def call(record)
        return unless apply_filters(record)

        out = apply_transforms(record)
        @sink.index(out) if @sink.respond_to?(:index)
        out
      end

      private

      def apply_filters(record)
        @filters.all? { |f| invoke(f, record) }
      end

      def apply_transforms(record)
        @transforms.reduce(record) { |memo, t| invoke(t, memo) }
      end

      def invoke(filter_or_transform, record)
        callable = filter_or_transform.is_a?(Class) ? filter_or_transform.new : filter_or_transform
        callable.call(record)
      end
    end
  end
end
