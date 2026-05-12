# frozen_string_literal: true

require "spec_helper"

class CorePluginCliBaseSpecOk < EmTools::Core::Plugin::Cli::Base
  attr_reader :captured_options, :captured_argv

  def banner = "Usage: em-tools spec:ok [--flag] [--n N] ARG"

  def defaults = { flag: false, n: 1 }

  def configure(opts, options)
    opts.on("--flag") { options[:flag] = true }
    opts.on("--n N", Integer) { |v| options[:n] = v }
  end

  def execute!(options, argv)
    @captured_options = options
    @captured_argv = argv
  end
end

class CorePluginCliBaseSpecConfigErr < EmTools::Core::Plugin::Cli::Base
  def execute!(_options, _argv)
    raise EmTools::Core::Errors::ConfigurationError, "missing FOO_URL"
  end
end

RSpec.describe(EmTools::Core::Plugin::Cli::Base) do
  describe "#run" do
    it "parses options and forwards remaining argv to execute!" do
      cmd = CorePluginCliBaseSpecOk.new
      cmd.run(["--flag", "--n", "7", "positional"])

      expect(cmd.captured_options).to(eq(flag: true, n: 7))
      expect(cmd.captured_argv).to(eq(["positional"]))
    end

    it "exits 0 on --help and prints the banner" do
      cmd = CorePluginCliBaseSpecOk.new
      expect { cmd.run(["--help"]) }
        .to(output(/spec:ok/).to_stdout
          .and(raise_error(SystemExit) { |e| expect(e.status).to(eq(0)) }))
    end

    it "translates ConfigurationError to a stderr message + exit(2)" do
      cmd = CorePluginCliBaseSpecConfigErr.new
      expect { cmd.run([]) }
        .to(output(/error: missing FOO_URL/).to_stderr
          .and(raise_error(SystemExit) { |e| expect(e.status).to(eq(2)) }))
    end

    it "raises NotImplementedError when execute! is not overridden" do
      bare = Class.new(described_class).new
      expect { bare.run([]) }.to(raise_error(NotImplementedError, /execute!/))
    end
  end
end
