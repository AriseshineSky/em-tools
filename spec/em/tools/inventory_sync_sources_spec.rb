# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Em::Tools::InventorySyncSources do
  it 'loads inventory URIs from merged settings when no path is given' do
    entries = described_class.load!
    expect(entries).not_to be_empty
    expect(entries.first.gs_uri).to match(%r{\Ags://}i)
  end
end
