# frozen_string_literal: true

require "spec_helper"

RSpec.describe(EmTools::Plugins::Amazon::Uploadable::Sources::EsAsins) do
  let(:client) { instance_double(EmTools::Clients::ElasticsearchClient) }

  it "streams normalized ASINs from the configured Elasticsearch index" do
    source = described_class.new(client: client, marketplace: "de", index: "custom_asins", max_asins: 2)

    expect(client).to(receive(:iterate_query)) do |index:, query:, batch_size:, max_hits:, &block|
      expect(index).to(eq("custom_asins"))
      expect(query).to(include(:bool))
      expect(batch_size).to(eq(described_class::DEFAULT_BATCH_SIZE))
      expect(max_hits).to(eq(2))
      block.call("_id" => "b000000001", "_source" => {})
      block.call("_id" => "invalid", "_source" => {})
    end

    expect(source.to_a).to(eq(["B000000001"]))
  end
end
