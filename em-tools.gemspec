# frozen_string_literal: true

require_relative "lib/em/tools/version"

Gem::Specification.new do |spec|
  spec.name = "em-tools"
  spec.version = Em::Tools::VERSION
  spec.authors = ["SmileintheSky"]
  spec.email = ["befruitful12@gmail.com"]

  spec.summary = "mono repo for em tools."
  spec.description = "mono repo for em tools."
  spec.homepage = ""
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["allowed_push_host"] = ""
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/AriseshineSky/em-tools"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "zeitwerk", "~> 2.0"
  spec.add_dependency "elasticsearch", "~> 7.17"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
