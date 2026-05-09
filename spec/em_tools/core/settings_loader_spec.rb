# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe EmTools::Core::SettingsLoader do
  around do |example|
    prev = ENV.fetch('APP_ENV', nil)
    ENV['APP_ENV'] = 'development'
    example.run
    prev ? ENV['APP_ENV'] = prev : ENV.delete('APP_ENV')
  end

  it 'deep-merges default with the active env section' do
    Tempfile.create(['em-tools-settings', '.yml']) do |f|
      f.write(<<~YAML)
        default:
          elasticsearch:
            url: http://default:9200
          redis:
            url: redis://default/0
        development:
          elasticsearch:
            url: http://dev:9200
      YAML
      f.flush
      h = described_class.load(f.path)
      expect(h.dig('elasticsearch', 'url')).to eq('http://dev:9200')
      expect(h.dig('redis', 'url')).to eq('redis://default/0')
    end
  end

  it 'returns empty hash for a missing file' do
    path = File.join(Dir.tmpdir, "missing-settings-#{Process.pid}.yml")
    expect(described_class.load(path)).to eq({})
  end

  it 'builds per-site env prefix' do
    expect(described_class.site_env_prefix('my-partner')).to eq('EM_TOOLS_SITE_MY_PARTNER_')
  end

  it 'resolves default_path to an existing file (example when config/settings.yml absent)' do
    p = described_class.default_path
    expect(File.file?(p)).to be(true)
    expect(p).to end_with('.yml')
  end
end
