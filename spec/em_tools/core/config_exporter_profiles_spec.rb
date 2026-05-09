# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'EmTools::Core::Config exporter / cluster ES URLs' do
  around do |example|
    EmTools::Core::Config.reload!
    prev_path = ENV['EM_TOOLS_SETTINGS_PATH']
    prev_es = ENV['ELASTICSEARCH_URL']
    prev_data = ENV['DATA_ELASTICSEARCH_URL']
    ENV['EM_TOOLS_SETTINGS_PATH'] = File.expand_path('../../../examples/config/settings.example.yml', __dir__)
    ENV['ELASTICSEARCH_URL'] = 'http://localhost:9200'
    ENV['DATA_ELASTICSEARCH_URL'] = 'http://34.16.105.219:9200'
    EmTools::Core::Config.reload!
    example.run
    ENV['EM_TOOLS_SETTINGS_PATH'] = prev_path
    prev_es.nil? ? ENV.delete('ELASTICSEARCH_URL') : ENV['ELASTICSEARCH_URL'] = prev_es
    prev_data.nil? ? ENV.delete('DATA_ELASTICSEARCH_URL') : ENV['DATA_ELASTICSEARCH_URL'] = prev_data
    EmTools::Core::Config.reload!
  end

  it 'resolves exporter cluster via DATA_ELASTICSEARCH_URL for cluster data' do
    expect(EmTools::Core::Config.exporter_elasticsearch_url('lotteon_products')).to eq('http://34.16.105.219:9200')
  end

  it 'returns exporter index from settings' do
    expect(EmTools::Core::Config.exporter_index('lotteon_products', 'fallback')).to eq('user1_lotteon_products')
  end

  it 'falls back to default elasticsearch_url when exporter is unknown' do
    expect(EmTools::Core::Config.exporter_elasticsearch_url('unknown_exporter')).to eq(
      EmTools::Core::Config.elasticsearch_url
    )
  end

  it 'exposes data_elasticsearch_url from ENV' do
    expect(EmTools::Core::Config.data_elasticsearch_url).to eq('http://34.16.105.219:9200')
  end
end
