# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Blacklist Live API', :live do
  it 'fetches real blacklist keywords from API' do
    skip 'Live test disabled' unless ENV['RUN_LIVE_TESTS'] == 'true'

    # ensure config exists
    expect(Em::Tools::Config.blacklist_api_endpoint).not_to be_nil
    expect(Em::Tools::Config.blacklist_api_token).not_to be_nil

    loader = Em::Tools::Blacklist::Loader.new
    keywords = loader.fetch_keywords

    expect(keywords).to be_an(Array)
    expect(keywords).to all(be_a(String))
    expect(keywords).not_to be_empty
  end
end
