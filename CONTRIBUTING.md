# Contributing

Thanks for taking the time to contribute to **em-tools**. The project is a
small, plugin-driven data-management platform — the conventions below keep
that surface tidy.

> em-tools is **not a gem**. It is a Ruby application meant to be run from a
> checkout via `bin/em-tools`, scheduled via cron / systemd timers under
> `schedule/`. There is no `.gemspec`, no `rake build/install/release`,
> nothing to publish.

## Development setup

```bash
git clone git@github.com:AriseshineSky/em-tools.git
cd em-tools
bin/setup                          # bundle install + .env scaffold
$EDITOR .env                       # fill in real cluster URLs / GCS keys
```

Run the full check before opening a PR:

```bash
bundle exec rspec
bundle exec rubocop
bundle exec bin/em-tools help      # sanity: CLI still boots
```

## Project layout

```
bin/em-tools                       # CLI executable (bundle exec bin/em-tools)
bin/console                        # IRB with em-tools loaded
bin/setup                          # bundle install + .env scaffold
lib/em_tools.rb                    # Zeitwerk + plugin auto-load
lib/em_tools/core/                 # core engine, errors, settings, CLI plumbing, sinks/sources
lib/em_tools/clients/              # external service clients (Spree, GCS, ES, exchange-rate)
lib/em_tools/plugins/<scope>/      # one directory per business plugin
config/settings.yml                # structural / routing config (no secrets)
.env.example                       # secrets and cluster URLs (copy to .env)
schedule/                          # cron + systemd templates for recurring jobs
docs/                              # OVERVIEW, CLI, CONFIGURATION, PLUGINS, ARCHITECTURE
spec/                              # RSpec mirror of lib/
```

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and
[`docs/PLUGINS.md`](docs/PLUGINS.md) for the engine + plugin contract.

## Coding style

- Style is enforced by [`rubocop-shopify`](https://github.com/Shopify/ruby-style-guide);
  see [`.rubocop.yml`](.rubocop.yml).
- Prefer explicit pipeline / runner classes over fattening the CLI command.
- Avoid narrating-comments. Comments should explain non-obvious *intent* or
  trade-offs, not the code line below them.
- Public-API methods get a YARD-style block comment with `@param` / `@return`.
- Tests must keep green before every commit.

## Branching & commits

- Branch from `main` (`feature/<short-slug>`, `fix/<short-slug>`, etc.).
- Conventional Commits (`feat:`, `fix:`, `chore:`, `refactor:`, `docs:`) are
  preferred but not strictly required.
- Squash trivial commits before opening the PR; keep each remaining commit a
  single, reviewable unit.

## Pull requests

Each PR should:

1. Describe **what** changed and **why** (link to relevant issue when applicable).
2. Update [`CHANGELOG.md`](CHANGELOG.md) under the `[Unreleased]` section if it
   is user-visible.
3. Update the relevant docs under `docs/` if behaviour, configuration, the
   CLI surface, or `schedule/` moved.
4. Pass `bundle exec rspec` and `bundle exec rubocop`.

## Adding a plugin

The plugin contract lives in [`docs/PLUGINS.md`](docs/PLUGINS.md). The short
version:

1. Create `lib/em_tools/plugins/<name>/plugin.rb` and have it inherit from
   `EmTools::Core::Plugin::Base`.
2. Declare the plugin's name and self-register in the plugin file:
   ```ruby
   def self.plugin_name = :my_plugin

   EmTools::Core::PluginRegistry.register(plugin_name, self)
   ```
3. Provide CLI commands by overriding `cli_commands` (each command lives under
   `cli/`) and expose business operations via plain instance methods on the
   plugin class.
4. Add specs under `spec/em_tools/plugins/<name>/`.

## Adding a scheduled job

`schedule/` is the source of truth for recurring jobs.

1. Pick the CLI subcommand the job should run.
2. Add either a line to [`schedule/cron.example`](schedule/cron.example) or
   a `em-tools-<job>.{service,timer}.example` pair under
   [`schedule/systemd/`](schedule/systemd/).
3. Mention the job in [`schedule/README.md`](schedule/README.md)'s table.

## Reporting issues

Open a GitHub issue with:

- The exact CLI invocation and arguments.
- Relevant environment variables (redacted) — see [`.env.example`](.env.example).
- The full error output (`em-tools` already prints clean one-liners for
  configuration / empty-result errors; everything else is a real bug).

Thanks again — we appreciate your help keeping em-tools small and sharp.
