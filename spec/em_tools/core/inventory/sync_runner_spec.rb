# frozen_string_literal: true

require 'spec_helper'

# -- spec
RSpec.describe EmTools::Core::Inventory::SyncRunner do
  describe '.resolve_single_gs_uri' do
    it 'prefers the cli arg' do
      uri = described_class.resolve_single_gs_uri(
        cli_gs_uri: 'gs://b/k.csv',
        env: { 'INVENTORY_GS_URI' => 'gs://other/x.csv' }
      )
      expect(uri).to eq('gs://b/k.csv')
    end

    it 'falls back to INVENTORY_GS_URI' do
      uri = described_class.resolve_single_gs_uri(env: { 'INVENTORY_GS_URI' => 'gs://b/k.csv' })
      expect(uri).to eq('gs://b/k.csv')
    end

    it 'composes from bucket+object' do
      uri = described_class.resolve_single_gs_uri(env: {
                                                    'INVENTORY_GCS_BUCKET' => 'my-b',
                                                    'INVENTORY_GCS_OBJECT' => '/path/feed.csv'
                                                  })
      expect(uri).to eq('gs://my-b/path/feed.csv')
    end

    it 'falls back to the default URI when nothing is provided' do
      expect(described_class.resolve_single_gs_uri(env: {})).to eq(described_class::DEFAULT_GS_URI)
    end

    it 'rejects malformed URIs with ConfigurationError' do
      expect do
        described_class.resolve_single_gs_uri(cli_gs_uri: 'not-a-gs-uri')
      end.to raise_error(EmTools::Core::Errors::ConfigurationError, /expected gs:/)
    end
  end

  describe '.require_elasticsearch_url!' do
    it 'raises when the env var is empty' do
      expect do
        described_class.require_elasticsearch_url!(env: {})
      end.to raise_error(EmTools::Core::Errors::ConfigurationError, /ELASTICSEARCH_URL/)
    end

    it 'is silent when the env var is set' do
      expect do
        described_class.require_elasticsearch_url!(env: { 'ELASTICSEARCH_URL' => 'http://x' })
      end.not_to raise_error
    end
  end

  describe '#run_one!' do
    it 'wires GcsBlobFetcher#with_downloaded into Sync#sync_from_path' do
      sink = instance_double('Sink')
      sync = instance_double(EmTools::Core::Inventory::Sync)
      fetcher = instance_double(EmTools::Clients::GcsBlobFetcher)
      allow(EmTools::Core::Inventory::Sync).to receive(:new).and_return(sync)
      allow(EmTools::Clients::GcsBlobFetcher).to receive(:new).and_return(fetcher)
      expect(fetcher).to receive(:with_downloaded).with('gs://b/x.csv').and_yield('/tmp/x.csv')
      expect(sync).to receive(:sync_from_path).with('/tmp/x.csv', refresh: true)

      described_class.new(sink: sink).run_one!(
        gs_uri: 'gs://b/x.csv', index: 'my_idx', feed_id: 'feed', refresh: true
      )
    end
  end
end
