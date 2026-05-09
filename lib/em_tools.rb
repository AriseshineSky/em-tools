# frozen_string_literal: true

require 'zeitwerk'

# Top-level namespace for the +em-tools+ gem.
#
# All code lives under +lib/em_tools/+ and is autoloaded by Zeitwerk via the
# canonical gem layout (see +Zeitwerk::Loader.for_gem+):
#
#   lib/em_tools/core/...    -> EmTools::Core::...
#   lib/em_tools/plugins/... -> EmTools::Plugins::...
#   lib/em_tools/clients/... -> EmTools::Clients::...
module EmTools
end

loader = Zeitwerk::Loader.for_gem
# Per-plugin Rake tasks live next to plugin source under +lib/em_tools/plugins/<name>/rakelib/+
# and are loaded by Rake itself, not by Zeitwerk.
loader.ignore("#{__dir__}/em_tools/plugins/*/rakelib")
loader.setup

EmTools::Core::SettingsHydrator.apply_if_blank!

# Eagerly load each plugin's +plugin.rb+ so it self-registers with
# +EmTools::Core::PluginRegistry+ at gem load time. The remaining plugin code is
# autoloaded on first reference.
Dir["#{__dir__}/em_tools/plugins/*/plugin.rb"].sort.each { |path| require path }
