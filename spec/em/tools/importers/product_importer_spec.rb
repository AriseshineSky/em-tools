# frozen_string_literal: true

require "spec_helper"
require "json"
require "stringio"
require "tempfile"

RSpec.describe Em::Tools::Importers::ProductImporter do
  def write_ndjson(lines)
    file = Tempfile.new(["products", ".ndjson"])
    file.write(lines.join("\n"))
    file.flush
    file
  end

  it "filters products and emits batch payloads" do
    file = write_ndjson([
      {"product_id" => "1", "price" => 39, "categories" => "Home > Kitchen", "title" => "Low price"}.to_json,
      {"product_id" => "2", "price" => 49, "categories" => "Gift Cards > Cards", "title" => "Blocked category"}.to_json,
      {"product_id" => "3", "price" => 50, "categories" => "Home > Tools", "brand" => "Acme", "title_en" => "Blacklisted item"}.to_json,
      {"product_id" => "4", "price" => 60, "categories" => "Home > Tools", "brand" => "Acme", "title" => "Clean item"}.to_json
    ])

    output = StringIO.new
    importer = described_class.new(
      store_code: "us",
      batch_size: 1,
      blacklist_keywords: ["blacklisted"]
    )

    result = importer.process(file.path, output: output)

    output.rewind
    payloads = output.readlines.map {|line| JSON.parse(line) }

    expect(result.invalid_products).to eq(0)
    expect(result.price_filtered_products).to eq(1)
    expect(result.category_filtered_products).to eq(1)
    expect(result.blacklisted_products).to eq(1)
    expect(result.accepted_products).to eq(1)
    expect(result.batches_emitted).to eq(1)
    expect(payloads.first["products"].first).not_to have_key("categories")
    expect(payloads.first["products"].first["product_id"]).to eq("4")
  ensure
    file.close
    file.unlink
  end
end
