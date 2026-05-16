# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"

module EmTools
  module Core
    module Translation
      # Google Cloud Translation **Basic API (v2)** with strict **character budgets**,
      # optional on-disk **cache** (avoid paying twice for the same string), **rate
      # limiting** between HTTP calls, and bounded **retries** on transient errors.
      #
      # Google bills by **source text characters**; this class counts with
      # +String#length+ (Unicode codepoints in Ruby). Callers should set
      # +max_billable_chars+ to a hard ceiling for the process (via
      # +EM_TRANSLATE_MAX_CHARS+ or {.from_config!}).
      #
      # @example Plugin use
      #   t = EmTools::Core::Translation::BudgetedTranslator.from_config!
      #   t.translate("안녕하세요", from: "ko", to: "en")
      #
      # @see https://docs.cloud.google.com/translate/docs/reference/libraries/v2/ruby
      class BudgetedTranslator
        attr_reader :chars_billed_this_session, :api_calls

        # @param max_billable_chars [Integer] hard cap on **new** billable source
        #   characters this instance will send to Google (cache hits do not count).
        # @param daily_char_cap [Integer] when >0, persist cumulative use per UTC day
        #   in +state_path+ (best-effort under concurrency; prefer a single worker).
        # @param state_path [String] JSON file for daily usage (+day+, +used+).
        # @param cache_dir [String, nil] when set, cache translations by digest.
        # @param max_chars_per_request [Integer] Google Basic limit is 5000 chars per
        #   request total across all strings; default 4500 leaves margin.
        # @param min_interval_between_calls [Float] minimum seconds **between** successive API calls.
        # @param max_retries [Integer] retries on transient failures (full batch retried).
        # @param project_id [String, nil] passed to V2 client (optional with ADC).
        # @param credentials [String, Hash, Google::Auth::Credentials, nil] path or hash.
        # @param key [String, nil] API key auth (alternative to service account).
        # @param v2_client [#translate] inject for tests (must match V2 +translate+ contract).
        # @param logger [::Logger, nil]
        def initialize(
          max_billable_chars:,
          daily_char_cap: 0,
          state_path: File.join("tmp", "translate_usage_state.json"),
          cache_dir: nil,
          max_chars_per_request: 4500,
          min_interval_between_calls: 0.35,
          max_retries: 3,
          project_id: nil,
          credentials: nil,
          key: nil,
          v2_client: nil,
          logger: nil
        )
          @max_billable_chars = Integer(max_billable_chars)
          if @max_billable_chars <= 0
            raise EmTools::Core::Errors::TranslationDisabledError,
              "max_billable_chars must be positive (set EM_TRANSLATE_MAX_CHARS)"
          end

          @daily_char_cap = Integer(daily_char_cap)
          @state_path = state_path.to_s
          @cache_dir = cache_dir&.to_s
          @max_chars_per_request = [Integer(max_chars_per_request), 1].max
          @min_interval = Float(min_interval_between_calls)
          @max_retries = [Integer(max_retries), 1].max
          @project_id = project_id
          @credentials = credentials
          @api_key = key
          @logger = logger || EmTools::Core::Logger.for(progname: "translate")
          @v2_client = v2_client || build_v2_client

          @chars_billed_this_session = 0
          @api_calls = 0
          @mutex = Mutex.new
          @last_api_end_monotonic = nil
        end

        # Builds from {EmTools::Core::Config} + environment. Raises when disabled.
        #
        # @raise [EmTools::Core::Errors::TranslationDisabledError]
        def self.from_config!(logger: nil)
          max = EmTools::Core::Config.translate_max_billable_chars
          if max <= 0
            raise EmTools::Core::Errors::TranslationDisabledError,
              "Translation disabled: set EM_TRANSLATE_MAX_CHARS or translate.max_billable_chars to a positive integer"
          end

          daily = EmTools::Core::Config.translate_daily_char_cap
          new(
            max_billable_chars: max,
            daily_char_cap: daily,
            state_path: EmTools::Core::Config.translate_state_path,
            cache_dir: EmTools::Core::Config.translate_cache_dir,
            max_chars_per_request: EmTools::Core::Config.translate_max_chars_per_request,
            min_interval_between_calls: EmTools::Core::Config.translate_min_interval_seconds,
            max_retries: EmTools::Core::Config.translate_max_retries,
            logger: logger,
          )
        end

        # @return [BudgetedTranslator, nil] nil when max billable chars is 0 / unset.
        def self.try_from_config(logger: nil)
          return if EmTools::Core::Config.translate_max_billable_chars <= 0

          from_config!(logger: logger)
        end

        # @param text [String]
        # @param from [String, nil] ISO-639-1 source language or nil for auto-detect.
        # @param to [String] ISO-639-1 target language (required).
        # @param format [Symbol, nil] +:text+ or +:html+ (V2 default is HTML-like behaviour).
        # @param model [String, nil] +"nmt"+ or +"base"+.
        # @return [String]
        def translate(text, to:, from: nil, format: nil, model: nil)
          many([text], to: to, from: from, format: format, model: model).first
        end

        # @param texts [Array<String>]
        # @return [Array<String>] same order and length as +texts+ (empty strings preserved).
        def translate_many(texts, to:, from: nil, format: nil, model: nil)
          many(Array(texts), to: to, from: from, format: format, model: model)
        end

        private

        def many(texts, to:, from:, format:, model:)
          list = texts.map(&:to_s)
          out = Array.new(list.length)

          list.each_with_index do |segment, idx|
            out[idx] = "" if segment.empty?
          end

          work_indices = list.each_index.select { |i| char_units(list[i]).positive? }
          return out if work_indices.empty?

          # Resolve cache hits without billing.
          uncached_segments = []
          uncached_indices = []
          work_indices.each do |i|
            seg = list[i]
            cached = read_cache(cache_key(seg, from: from, to: to, format: format, model: model))
            if cached
              out[i] = cached
            else
              uncached_indices << i
              uncached_segments << seg
            end
          end

          return out if uncached_segments.empty?

          batches = chunk_by_char_budget(uncached_segments, @max_chars_per_request)
          translations_flat = []

          batches.each do |batch|
            needed = batch.sum { |s| char_units(s) }
            assert_room_for_billable_chars!(needed)
            wait_for_rate_limit!

            results = with_retries do
              invoke_translate_api(batch, to: to, from: from, format: format, model: model)
            end
            mark_api_completed!

            unless results.length == batch.length
              raise EmTools::Error, "Translate API returned #{results.length} results for #{batch.length} inputs"
            end

            batch.each_with_index do |src, j|
              tr = results[j]
              text_out = tr.respond_to?(:text) ? tr.text.to_s : tr.to_s
              translations_flat << text_out
              write_cache(
                cache_key(src, from: from, to: to, format: format, model: model),
                text_out,
              )
            end

            record_billable_chars!(needed)
            @mutex.synchronize { @api_calls += 1 }
          end

          uncached_indices.each_with_index do |orig_idx, j|
            out[orig_idx] = translations_flat[j]
          end

          out
        end

        def char_units(str)
          str.to_s.length
        end

        def chunk_by_char_budget(strings, max_chars)
          batches = []
          current = []
          size = 0
          strings.each do |s|
            u = char_units(s)
            raise EmTools::Core::Errors::ConfigurationError, "single segment exceeds max_chars_per_request (#{u} > #{max_chars})" if u > max_chars

            if !current.empty? && (size + u > max_chars)
              batches << current
              current = []
              size = 0
            end
            current << s
            size += u
          end
          batches << current unless current.empty?
          batches
        end

        def assert_room_for_billable_chars!(needed)
          @mutex.synchronize do
            if @chars_billed_this_session + needed > @max_billable_chars
              raise EmTools::Core::Errors::TranslationBudgetExceededError,
                "session character budget exceeded: would use #{@chars_billed_this_session + needed} > #{@max_billable_chars}"
            end
          end

          return if @daily_char_cap <= 0

          with_usage_lock do |f|
            day, used = read_usage_payload(f)
            if used + needed > @daily_char_cap
              raise EmTools::Core::Errors::TranslationBudgetExceededError,
                "daily character budget exceeded: would use #{used + needed} > #{@daily_char_cap} (UTC day #{day})"
            end
          end
        end

        def record_billable_chars!(needed)
          @mutex.synchronize { @chars_billed_this_session += needed }

          return if @daily_char_cap <= 0

          with_usage_lock do |f|
            day, used = read_usage_payload(f)
            used += needed
            write_usage_payload(f, day, used)
          end
        end

        def with_usage_lock
          FileUtils.mkdir_p(File.dirname(@state_path))
          File.open(@state_path, File::RDWR | File::CREAT, 0o644) do |f|
            f.flock(File::LOCK_EX)
            yield f
          end
        end

        def read_usage_payload(file)
          file.rewind
          raw = file.read
          data =
            begin
              raw.strip.empty? ? {} : JSON.parse(raw)
            rescue JSON::ParserError
              {}
            end
          today = Time.now.utc.strftime("%Y-%m-%d")
          day = data["day"].to_s
          used = data["used"].to_i
          if day != today
            day = today
            used = 0
          end
          [day, used]
        end

        def write_usage_payload(file, day, used)
          file.truncate(0)
          file.rewind
          file.write(JSON.generate("day" => day, "used" => used))
          file.flush
        end

        def wait_for_rate_limit!
          return if @min_interval <= 0

          @mutex.synchronize do
            now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
            if @last_api_end_monotonic
              wait = @min_interval - (now - @last_api_end_monotonic)
              sleep(wait) if wait.positive?
            end
          end
        end

        def mark_api_completed!
          return if @min_interval <= 0

          @mutex.synchronize do
            @last_api_end_monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          end
        end

        def with_retries
          attempts = 0
          begin
            attempts += 1
            yield
          rescue EmTools::Core::Errors::TranslationBudgetExceededError,
                 EmTools::Core::Errors::TranslationDisabledError,
                 EmTools::Core::Errors::ConfigurationError
            raise
          rescue StandardError => e
            if attempts >= @max_retries
              @logger.error { "translate failed after #{attempts} attempts: #{e.class}: #{e.message}" }
              raise
            end
            backoff = 0.5 * (2**(attempts - 1))
            @logger.warn { "translate retry #{attempts}/#{@max_retries} after #{e.class}: sleeping #{backoff}s" }
            sleep(backoff)
            retry
          end
        end

        def invoke_translate_api(batch, to:, from:, format:, model:)
          kwargs = { to: to.to_s }
          src = from&.to_s&.strip
          kwargs[:from] = src if src && !src.empty?
          kwargs[:format] = format.to_sym if format
          m = model&.to_s&.strip
          kwargs[:model] = m if m && !m.empty?

          result = @v2_client.translate(*batch, **kwargs)
          Array(result)
        end

        def build_v2_client
          require "google/cloud/translate/v2"

          kwargs = { retries: 2, timeout: 60 }
          kwargs[:project_id] = @project_id if @project_id
          kwargs[:credentials] = @credentials if @credentials
          kwargs[:key] = @api_key if @api_key
          Google::Cloud::Translate::V2.new(**kwargs)
        end

        def cache_key(text, from:, to:, format:, model:)
          parts = [
            from.to_s,
            to.to_s,
            format.to_s,
            model.to_s,
            text,
          ]
          Digest::SHA256.hexdigest(parts.join("\u{1e}"))
        end

        def read_cache(digest)
          return unless @cache_dir

          path = cache_path_for(digest)
          return unless File.file?(path)

          JSON.parse(File.read(path, encoding: Encoding::UTF_8))["text"].to_s
        rescue JSON::ParserError, Errno::ENOENT
          nil
        end

        def write_cache(digest, translated)
          return unless @cache_dir

          path = cache_path_for(digest)
          FileUtils.mkdir_p(File.dirname(path))
          tmp = "#{path}.#{Process.pid}.tmp"
          payload = JSON.generate("text" => translated, "v" => 1)
          File.write(tmp, payload, mode: "wb")
          File.rename(tmp, path)
        rescue StandardError => e
          @logger.warn { "translate cache write failed: #{e.message}" }
        end

        def cache_path_for(digest)
          File.join(@cache_dir, digest[0, 2], digest[2, 2], "#{digest}.json")
        end
      end
    end
  end
end
