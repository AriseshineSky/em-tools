# frozen_string_literal: true

namespace :es do
  desc 'Dump ES index to NDJSON; primary cluster unless ES_DUMP_ELASTICSEARCH_URL is set. ' \
       'Env: ES_DUMP_INDEX (default user1_lotteon_products), ES_DUMP_OUTPUT (default tmp/<index>.ndjson), ' \
       'ES_DUMP_BATCH_SIZE (default 1000).'
  task :dump_index do
    EmTools::Core::RakeSupport.run do
      EmTools::Core::Sinks::IndexDumper.from_env(prefer_data_cluster: false).run!
    end
  end

  desc 'Dump Lotteon index from DATA_ELASTICSEARCH_URL (or ES_DUMP_ELASTICSEARCH_URL override).'
  task :download_product do
    EmTools::Core::RakeSupport.run do
      EmTools::Core::Sinks::IndexDumper.from_env(prefer_data_cluster: true).run!
    end
  end
end

desc 'Alias for es:download_product.'
task download_product: 'es:download_product'
