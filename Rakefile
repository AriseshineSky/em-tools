# frozen_string_literal: true

# rubocop:disable Lint/SuppressedException
begin
  require 'dotenv/load'
rescue LoadError
end
# rubocop:enable Lint/SuppressedException

require 'bundler/gem_tasks'
require 'rake'
require 'em_tools'

# Each plugin can opt into adding its own +rakelib/+ to Rake's default load path. We collect every
# +rake_load_paths+ entry from registered plugins and prepend them to +Rake.application.options.rakelib+.
# Top-level +rakelib/*.rake+ continues to load by default (Rake convention) for genuinely global tasks
# like +inventory:sync+ and +es:dump_index+.
plugin_rakelib_paths = []
EmTools::Core::PluginRegistry.each_plugin do |plugin|
  Array(plugin.rake_load_paths).each do |path|
    plugin_rakelib_paths << path if File.directory?(path)
  end
end

if plugin_rakelib_paths.any?
  Rake.application.options.rakelib = (Rake.application.options.rakelib + plugin_rakelib_paths).uniq
end

task default: %i[]
