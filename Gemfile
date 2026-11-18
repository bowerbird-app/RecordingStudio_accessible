# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in recording_studio_accessible.gemspec
gemspec

gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v7.7.1"
# Git-only, and not an Accessible dependency. Admin and API depend on it, so
# the root bundle needs this pin to resolve. require: false — Accessible does
# not load Trashable. The dummy app loads the query entry itself.
gem "recording_studio_trashable", github: "bowerbird-app/RecordingStudio_trashable",
                                  tag: "v1.2.0", require: false
# Git-only companion deps. Pin by release tag so Bundler can resolve them.
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.378",
                 require: false

gem "minitest", ">= 5.26", "< 6"
gem "view_component", "4.19.0"

gem "recording_studio_metrics", github: "bowerbird-app/RecordingStudio_metrics", tag: "v0.9.1",
                                require: false
# Email-code accounts. Soft-required: Users already depends on Accessible.
# Users, Admin, and Attachable gemspec deps are git-only; pin them so Bundler can resolve.
gem "recording_studio_admin", github: "bowerbird-app/RecordingStudio_admin", tag: "v2.19.0",
                              require: false
gem "recording_studio_api", github: "bowerbird-app/RecordingStudio_api", tag: "v1.15.0",
                            require: false
gem "recording_studio_attachable", github: "bowerbird-app/RecordingStudio_attachable", tag: "v0.32.1",
                                   require: false
gem "recording_studio_cache", github: "bowerbird-app/RecordingStudio_cache", tag: "v0.7.0",
                              require: false
gem "recording_studio_icons", github: "bowerbird-app/RecordingStudio_icons", tag: "v0.4.1",
                              require: false
gem "recording_studio_logs", github: "bowerbird-app/RecordingStudio_logs", tag: "v0.8.1",
                             require: false
gem "recording_studio_moveable", github: "bowerbird-app/RecordingStudio_moveable", tag: "v6.0.1",
                                 require: false
gem "recording_studio_user", github: "bowerbird-app/RecordingStudio_users", tag: "v0.36.0",
                             require: false

gem "devise"
gem "importmap-rails"
gem "pg"
gem "puma", "~> 7.2.1"
gem "sprockets-rails"
gem "tailwindcss-rails"

group :development, :test do
  gem "bootsnap", require: false
  gem "debug"
  gem "minitest-mock"
  gem "simplecov", require: false
end

group :development do
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
end
