# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Em::Tools::Amazon::PriceRules do
  describe '.from_config' do
    it 'uses defaults when config empty' do
      rules = described_class.from_config({}, marketplace: 'de')
      expect(rules.to_h).to eq(described_class::DEFAULTS)
    end

    it 'reads nested price.rules.amz_<mp>' do
      cfg = { 'price' => { 'rules' => { 'amz_de' => { 'roi' => 0.5, 'ad_cost' => 3 } } } }
      rules = described_class.from_config(cfg, marketplace: 'de')
      expect(rules.to_h[:roi]).to eq(0.5)
      expect(rules.to_h[:ad_cost]).to eq(3.0)
      expect(rules.to_h[:transfer_cost]).to eq(0.0)
    end

    it 'reads flat price.rules.amz_<mp> key' do
      cfg = { 'price.rules.amz_us' => { 'roi' => '0.25' } }
      rules = described_class.from_config(cfg, marketplace: 'us')
      expect(rules.to_h[:roi]).to eq(0.25)
    end
  end
end
