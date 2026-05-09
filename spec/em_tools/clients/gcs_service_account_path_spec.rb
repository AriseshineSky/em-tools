# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe EmTools::Clients::GcsServiceAccountPath do
  around do |example|
    prev = ENV.fetch('GCS_SERVICE_ACCOUNT_PATH', nil)
    example.run
    prev ? ENV['GCS_SERVICE_ACCOUNT_PATH'] = prev : ENV.delete('GCS_SERVICE_ACCOUNT_PATH')
  end

  describe '.default_path' do
    it 'expands ~/.em_celery/gcs-sa.json under Dir.home' do
      expect(described_class.default_path).to eq(
        File.expand_path(File.join(Dir.home, '.em_celery', 'gcs-sa.json'))
      )
    end
  end

  describe '.resolve' do
    it 'uses Dir.home default when env is unset' do
      ENV.delete('GCS_SERVICE_ACCOUNT_PATH')
      expect(described_class.resolve).to eq(described_class.default_path)
    end

    it 'honors GCS_SERVICE_ACCOUNT_PATH when set' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'key.json')
        File.write(path, '{}')
        ENV['GCS_SERVICE_ACCOUNT_PATH'] = path
        expect(described_class.resolve).to eq(File.expand_path(path))
      end
    end
  end
end
