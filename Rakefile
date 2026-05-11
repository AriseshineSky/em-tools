# frozen_string_literal: true

# em-tools is driven by the +bin/em-tools+ CLI; this Rakefile only exists to
# expose +rake spec+ for editor / CI integrations. There is intentionally
# nothing else here — no gem build / install / release tasks, no business
# tasks. All operational workflows go through the CLI; recurring jobs are
# wired up via cron / systemd timers (see +schedule/+).

require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec
