# frozen_string_literal: true

require "dry/cli"
require "json"

module EmTools
  module Plugins
    module Amazon
      module Uploadable
        module Cli
          # +em-tools amazon products upload-from-es+ — Ruby port of the Click command in
          # em-celery +amz_upload_products_from_es.py+ (+filter_products+).
          class AmzUploadProductsFromEs < Dry::CLI::Command
            desc "Stream ASINs and write them out (file or stdout); Celery-parity command"

            option :marketplace, aliases: ["-m"], default: "us", desc: "Amazon marketplace (default: us)"
            option :ttl,
              aliases: ["-t"],
              default: "30",
              desc: "Offer TTL days (default: 30; informational in Ruby)"
            option :config, desc: "YAML merged into stream + price rule resolution"
            option :output, aliases: ["-o"], desc: "Write ASINs to file instead of stdout"
            option :dry_run, type: :flag, default: false, desc: "Print resolved manifest JSON and exit"
            option :max_asins, desc: "Stop after N ASINs (testing)"

            example [
              "-m de",
              "-m de --dry-run",
              "-m de -o asins.txt --config examples/config/amz_celery_compat.example.yml",
            ]

            def call(marketplace: "us", ttl: "30", config: nil, output: nil,
              dry_run: false, max_asins: nil, **)
              cfg = config ? EmTools::Core::Cli::Support.load_yaml_file!(config) : {}
              plugin = EmTools::Core::PluginRegistry.fetch(:amazon)
              runner = plugin.upload_runner(
                marketplace: marketplace,
                ttl: Integer(ttl),
                config: cfg,
              )

              if dry_run
                $stdout.puts(JSON.generate(runner.describe))
                return
              end

              EmTools::Core::Cli::Support.require_elasticsearch_url!

              io = output ? File.open(output, "w") : $stdout
              begin
                runner.run!(
                  client: plugin.dependencies[:es_client],
                  io: io,
                  max_asins: max_asins ? Integer(max_asins) : nil,
                )
              ensure
                io.close if output
              end
            end
          end
        end
      end
    end
  end
end
