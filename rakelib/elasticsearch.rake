# frozen_string_literal: true

require 'json'
require 'fileutils'

# rubocop:disable Metrics/BlockLength -- Rake task bodies
namespace :es do
  desc 'Dump ES index to NDJSON; primary cluster unless ES_DUMP_ELASTICSEARCH_URL is set.'
  task :dump_index do
    require 'bundler/setup'
    # rubocop:disable Lint/SuppressedException
    begin
      require 'dotenv/load'
    rescue LoadError
    end
    # rubocop:enable Lint/SuppressedException
    require 'em/tools'

    explicit = ENV['ES_DUMP_ELASTICSEARCH_URL'].to_s.strip
    explicit = nil if explicit.empty?
    url = Em::Tools::Config.elasticsearch_connection_url(explicit: explicit, prefer_data_cluster: false)

    index = ENV.fetch('ES_DUMP_INDEX', 'user1_lotteon_products')
    out_path = ENV['ES_DUMP_OUTPUT'] || File.join('tmp', "#{index}.ndjson")
    batch_size = ENV.fetch('ES_DUMP_BATCH_SIZE', '1000').to_i

    dir = File.dirname(out_path)
    FileUtils.mkdir_p(dir) unless dir == '.'

    client = Em::Clients::ElasticsearchClient.new(url: url)
    count = 0
    File.open(out_path, 'w') do |out|
      client.iterate_all(index: index, batch_size: batch_size) do |hit|
        out.puts(JSON.generate(hit))
        count += 1
      end
    end
    puts "Wrote #{count} hits to #{out_path}"
  end
end
# rubocop:enable Metrics/BlockLength

desc 'Dump Lotteon index from DATA_ELASTICSEARCH_URL (or ES_DUMP_ELASTICSEARCH_URL override).'
task :download_product do
  require 'bundler/setup'
  # rubocop:disable Lint/SuppressedException
  begin
    require 'dotenv/load'
  rescue LoadError
  end
  # rubocop:enable Lint/SuppressedException
  require 'em/tools'

  explicit = ENV['ES_DUMP_ELASTICSEARCH_URL'].to_s.strip
  explicit = nil if explicit.empty?
  url = Em::Tools::Config.elasticsearch_connection_url(explicit: explicit, prefer_data_cluster: true)

  index = ENV.fetch('ES_DUMP_INDEX', 'user1_lotteon_products')
  out_path = ENV['ES_DUMP_OUTPUT'] || File.join('tmp', "#{index}.ndjson")
  batch_size = ENV.fetch('ES_DUMP_BATCH_SIZE', '1000').to_i

  dir = File.dirname(out_path)
  FileUtils.mkdir_p(dir) unless dir == '.'

  client = Em::Clients::ElasticsearchClient.new(url: url)
  count = 0
  File.open(out_path, 'w') do |out|
    client.iterate_all(index: index, batch_size: batch_size) do |hit|
      out.puts(JSON.generate(hit))
      count += 1
    end
  end
  puts "Wrote #{count} hits to #{out_path}"
end
