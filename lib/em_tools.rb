# frozen_string_literal: true

require "zeitwerk"

# Top-level namespace and load entry point for the **em-tools** data
# management platform. em-tools is a project-local Ruby application, not a
# packaged gem: there is no +.gemspec+ and no +rake build/install/release+
# flow. Code is loaded by Zeitwerk, the executable lives at +bin/em-tools+,
# and recurring jobs are wired up via cron / systemd timers under
# +schedule/+.
#
# == Public surface (used by the CLI, plugins, and specs)
#
# - +EmTools::VERSION+              - diagnostic version of the running tree.
# - +EmTools::Error+                - base class for every gem-defined exception.
# - +EmTools::Core::Cli::App+       - CLI dispatcher driven by +bin/em-tools+.
# - +EmTools::Core::Cli::Runner+    - block runner that turns
#   +Errors::ConfigurationError+ / +Errors::EmptyResultError+ into +exit 1+.
# - +EmTools::Core::PluginRegistry+ - plugin lookup + iteration.
# - +EmTools::Core::Plugin::Base+   - base class plugins inherit from.
# - +EmTools::Core::Errors::*+      - configuration / empty-result errors.
# - +EmTools::Clients::*+           - external service clients (Spree, GCS, ES, etc).
#
# == Code layout
#
# All code lives under +lib/em_tools/+. Zeitwerk maps the directory tree to
# CamelCase constants:
#
#   lib/em_tools/core/...    -> EmTools::Core::...
#   lib/em_tools/plugins/... -> EmTools::Plugins::...
#   lib/em_tools/clients/... -> EmTools::Clients::...
#
# The CLI is the only operational entrypoint. See +docs/CLI.md+.
module EmTools
end

loader = Zeitwerk::Loader.new
loader.tag = "em_tools"
loader.push_dir(File.expand_path("../lib", __dir__))
loader.inflector.inflect("version" => "VERSION")
loader.setup

EmTools::Core::SettingsHydrator.apply_if_blank!

# Eagerly load each plugin's +plugin.rb+ so it self-registers with
# +EmTools::Core::PluginRegistry+ at boot. The remaining plugin code is
# autoloaded on first reference.
Dir["#{__dir__}/em_tools/plugins/*/plugin.rb"].sort.each { |path| require(path) }
