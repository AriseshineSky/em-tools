# frozen_string_literal: true

# em-tools is a personal data-management platform, not a published gem.
# All dependencies are declared directly here; there is no .gemspec.

source "https://rubygems.org"

ruby File.read(File.expand_path(".ruby-version", __dir__)).strip

# Runtime
gem "ahocorasick-rust", "~> 2.0"
gem "csv"
gem "elasticsearch", "~> 7.17"
gem "google-cloud-storage"
gem "nokogiri", "~> 1.19"
gem "zeitwerk", "~> 2.0"

group :development, :test do
  gem "debug"
  gem "dotenv"
  gem "irb"
  gem "rake", "~> 13.0"
  gem "rspec"
  gem "rubocop", require: false
  gem "rubocop-rspec", require: false
  gem "rubocop-shopify", require: false
end
