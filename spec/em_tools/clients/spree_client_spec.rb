# frozen_string_literal: true

require "tmpdir"

SpreeClientSpecResponse = Struct.new(:code, :body, :message, keyword_init: true)

class SpreeClientSpecFakeTransport
  attr_reader :calls

  def initialize(*responses)
    @responses = responses
    @calls = []
  end

  def request(uri, request, **_timeouts)
    @calls << [uri, request]
    @responses.shift || SpreeClientSpecResponse.new(code: "200", body: "{}", message: "OK")
  end

  def download(uri, request, output_path, **_timeouts)
    response = self.request(uri, request)
    File.binwrite(output_path, response.body.to_s) if response.code.to_i.between?(200, 299)
    response
  end
end

RSpec.describe(EmTools::Clients::SpreeClient) do
  def decoded_query(uri)
    URI.decode_www_form(uri.query).to_h
  end

  it "lists completed orders with Spree defaults and caller params" do
    transport = SpreeClientSpecFakeTransport.new(
      SpreeClientSpecResponse.new(code: "200", body: '{"orders":[]}', message: "OK"),
    )
    client = described_class.new("https://store.example.com/", "secret", transport: transport)

    expect(client.list_orders("page" => 3)).to(eq("orders" => []))

    uri, request = transport.calls.first
    expect(request).to(be_a(Net::HTTP::Get))
    expect(uri.to_s).to(start_with("https://store.example.com/api/v1/orders?"))
    expect(decoded_query(uri)).to(include(
      "token" => "secret",
      "q[completed_at_not_null]" => "1",
      "q[s]" => "completed_at:asc",
      "page" => "3",
      "per_page" => "50",
    ))
  end

  it "sends stock updates as JSON and returns the raw response" do
    response = SpreeClientSpecResponse.new(code: "200", body: '{"ok":true}', message: "OK")
    transport = SpreeClientSpecFakeTransport.new(response)
    client = described_class.new("https://store.example.com", "secret", transport: transport)

    expect(client.update_stock(42, 7, 3, force: false, backorderable: true)).to(eq(response))

    uri, request = transport.calls.first
    expect(uri.path).to(eq("/api/v1/stock_locations/3/stock_items/42"))
    expect(decoded_query(uri)).to(eq("token" => "secret"))
    expect(request["Content-Type"]).to(eq("application/json"))
    expect(JSON.parse(request.body)).to(eq(
      "stock_item" => {
        "count_on_hand" => 7,
        "force" => false,
        "backorderable" => true,
      },
    ))
  end

  it "downloads inventory to a fresh output file" do
    transport = SpreeClientSpecFakeTransport.new(
      SpreeClientSpecResponse.new(code: "200", body: "sku,count\nA,1\n", message: "OK"),
    )
    client = described_class.new("https://store.example.com", "secret", transport: transport)

    Dir.mktmpdir do |dir|
      output_path = File.join(dir, "nested", "inventory.csv")
      client.download_inventory("site-a", output_path)

      expect(File.binread(output_path)).to(eq("sku,count\nA,1\n"))
      uri, = transport.calls.first
      expect(uri.path).to(eq("/api/v1/inventory_reports/download"))
      expect(decoded_query(uri)).to(eq("token" => "secret", "source" => "site-a"))
    end
  end

  it "fills missing merchant ids when setting GMC custom labels" do
    transport = SpreeClientSpecFakeTransport.new(
      SpreeClientSpecResponse.new(code: "200", body: '{"updated":1}', message: "OK"),
    )
    client = described_class.new("https://store.example.com", "secret", transport: transport)

    result = client.set_gmc_custom_labels(99, [{ item_id: "A" }, { "other" => "skip" }])

    expect(result).to(eq("updated" => 1))
    _, request = transport.calls.first
    expect(JSON.parse(request.body)).to(eq(
      "entries" => [
        {
          "item_id" => "A",
          "merchant_id" => 99,
        },
      ],
    ))
  end

  it "returns the default shop" do
    transport = SpreeClientSpecFakeTransport.new(
      SpreeClientSpecResponse.new(
        code: "200",
        body: '{"stores":[{"id":1,"default":false},{"id":2,"default":true}]}',
        message: "OK",
      ),
    )
    client = described_class.new("https://store.example.com", "secret", transport: transport)

    expect(client.get_shop).to(eq("id" => 2, "default" => true))
    uri, = transport.calls.first
    expect(uri.path).to(eq("/api/v1/stores"))
  end
end
