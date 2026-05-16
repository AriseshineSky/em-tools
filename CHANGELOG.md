# Changelog

Notable changes to **em-tools**, the Everymarket data-management platform.
em-tools is a project-local Ruby application (not a published gem); the
"version" tag is operator-facing — bump it whenever the CLI surface, ES
schema, or scheduled-job set changes in a way the deployment cares about.

## [Unreleased]

### Added

- `bin/em-tools` — project executable invoked as `bundle exec bin/em-tools`.
- `bin/console` — IRB with em-tools auto-loaded.
- `bin/setup` — one-shot `bundle install` + `.env` scaffold.
- `schedule/` — first-class home for recurring-job templates:
  - `cron.example` (single-file crontab).
  - `systemd/em-tools-*.{service,timer}.example` for inventory sync,
    Amazon lowest-offer snapshot, and eBay listings snapshot.
- Hierarchical CLI tree (`em-tools <area> <action>`) backed by
  [dry-cli](https://dry-rb.org/gems/dry-cli/). Top-level discovery shows
  every namespace as a subtree; per-command help is auto-generated.

### Changed

- em-tools is no longer packaged as a gem. `em-tools.gemspec`,
  `bundler/gem_tasks`, and `exe/` are removed; the executable lives at
  `bin/em-tools` and dependencies are declared directly in `Gemfile`.
- `lib/em_tools.rb` switched from `Zeitwerk::Loader.for_gem` to an explicit
  `Zeitwerk::Loader.new + push_dir("lib")`.
- `EmTools::VERSION` is now defined in `lib/em_tools/version.rb`;
  `EmTools::Core::VERSION` is removed (single source of truth).
- `Rakefile` reduced to `rake spec`. There are no business rake tasks.
- **CLI shape: colon-style names → subcommand tree**. Every command moved to
  hierarchical paths: `inventory-sync` → `inventory sync`, `es-dump-index` →
  `es dump-index`, `lotteon:products:export` → `lotteon products export`,
  etc. No back-compat aliases — rename your cron / systemd units to match.
- Plugin contract: `Plugin#cli_commands` keys are now subcommand paths
  *relative* to `cli_namespace` (the registry prepends the namespace).
  `Plugin::Cli::Base` is removed; plugin commands inherit from
  `Dry::CLI::Command` directly.
- **Amazon plugins merged (breaking)**. `:amazon_uploadable` and
  `:amazon_lowest_offer` are a single `:amazon` plugin (`plugins/amazon/plugin.rb`);
  implementation modules live under `EmTools::Plugins::Amazon::Uploadable::*` and
  `EmTools::Plugins::Amazon::LowestOffer::*`. CLI: `amz-uploadable …` and
  `amazon-lowest-offer …` are replaced by `em-tools amazon products …` and
  `em-tools amazon coverage …`. Use `PluginRegistry.fetch(:amazon)` for both areas.
- **Storefront inventory CLI (breaking)**: `storefront sync-inventory` →
  `storefront inventory sync` (resource/action ordering).

### Removed

- **`BLACKLIST_API_KEY`**: no longer read or used as a fallback for
  `Config.blacklist_api_token`; set `BLACKLIST_API_TOKEN` only.
- `em-tools.gemspec` and the `bundler/gem_tasks` derived `rake build/install/release` tasks.
- `exe/` directory.
- `EmTools::Core::VERSION` constant.
- `Core::Cli::CommandRegistry`, `Core::Cli::HelpRenderer`,
  `Core::Cli::CommandNames`, `Core::Plugin::Cli::Base` — replaced wholesale
  by `Core::Cli::Registry` (a `Dry::CLI::Registry` builder) and the
  `Dry::CLI::Command` DSL on each command class.
- Core CLI duplicates of plugin commands (`lowest-offer-*`,
  `ebay-listings-*`); these are now reached via the plugin subtrees
  (`amazon coverage *`, `ebay listings *`).

## Earlier milestones

- Plugin-based architecture: core engine + per-marketplace plugins
  (`amazon/uploadable`, `amazon/lowest_offer`, `ebay`, `storefront`,
  `lotteon`, `ssg`); inventory sync stays core.
- Centralised CLI runner shim (`EmTools::Core::Cli::Runner`) that turns
  `ConfigurationError` / `EmptyResultError` into a clean `error: <msg>` +
  `exit 1`.
- `EmTools::Error` top-level base class so library callers can rescue any
  em-tools-specific failure.
- Documentation set under `docs/`: `OVERVIEW.md`, `CLI.md`,
  `CONFIGURATION.md`, `PLUGINS.md`, refreshed `ARCHITECTURE.md`.
- Project linting now inherits from
  [`rubocop-shopify`](https://github.com/Shopify/ruby-style-guide); the
  previous `rubocop-rails` / `rubocop-rake` plugins are removed.
- Initial extraction of the legacy `em-tasks` workflows into a Ruby project
  with a plugin-based architecture.
