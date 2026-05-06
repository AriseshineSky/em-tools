# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe Em::Tools::Config do
  around do |example|
    prev_settings = ENV['EM_TOOLS_SETTINGS_PATH']
    prev_app = ENV.fetch('APP_ENV', nil)
    prev_es = ENV.fetch('ELASTICSEARCH_URL', nil)
    example.run
    prev_settings ? ENV['EM_TOOLS_SETTINGS_PATH'] = prev_settings : ENV.delete('EM_TOOLS_SETTINGS_PATH')
    prev_app ? ENV['APP_ENV'] = prev_app : ENV.delete('APP_ENV')
    prev_es ? ENV['ELASTICSEARCH_URL'] = prev_es : ENV.delete('ELASTICSEARCH_URL')
    described_class.reload!
  end

  it 'prefers ELASTICSEARCH_URL over YAML' do
    Tempfile.create(['cfg', '.yml']) do |f|
      f.write(<<~YAML)
        default:
          elasticsearch:
            url: http://from-yaml:9200
        development: {}
      YAML
      f.flush
      ENV['EM_TOOLS_SETTINGS_PATH'] = f.path
      ENV['APP_ENV'] = 'development'
      ENV['ELASTICSEARCH_URL'] = 'http://from-env:9200'
      described_class.reload!
      expect(described_class.elasticsearch_url).to eq('http://from-env:9200')
    end
  end

  it 'reads elasticsearch url from settings when ENV is unset' do
    Tempfile.create(['cfg', '.yml']) do |f|
      f.write(<<~YAML)
        default:
          elasticsearch:
            url: http://yaml-only:9200
        development: {}
      YAML
      f.flush
      ENV['EM_TOOLS_SETTINGS_PATH'] = f.path
      ENV['APP_ENV'] = 'development'
      ENV.delete('ELASTICSEARCH_URL')
      described_class.reload!
      expect(described_class.elasticsearch_url).to eq('http://yaml-only:9200')
    end
  end

  it 'raises when elasticsearch url is nowhere to be found' do
    Tempfile.create(['cfg', '.yml']) do |f|
      f.write("default: {}\ndevelopment: {}\n")
      f.flush
      ENV['EM_TOOLS_SETTINGS_PATH'] = f.path
      ENV['APP_ENV'] = 'development'
      ENV.delete('ELASTICSEARCH_URL')
      described_class.reload!
      expect { described_class.elasticsearch_url }.to raise_error(RuntimeError, /ELASTICSEARCH_URL/)
    end
  end

  it 'exposes site() merged with env overrides' do
    Tempfile.create(['cfg', '.yml']) do |f|
      f.write(<<~YAML)
        default:
          sites:
            acme:
              endpoint: https://yaml.example/api
              token: ""
        development: {}
      YAML
      f.flush
      ENV['EM_TOOLS_SETTINGS_PATH'] = f.path
      ENV['APP_ENV'] = 'development'
      ENV['EM_TOOLS_SITE_ACME_TOKEN'] = 'secret'
      described_class.reload!
      s = described_class.site('acme')
      expect(s['endpoint']).to eq('https://yaml.example/api')
      expect(s['token']).to eq('secret')
    end
  end
end
