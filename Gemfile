# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in recording_studio_accessible.gemspec
gemspec

gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v4.5.0"
# Trashable owns trashed_at helpers used by Accessible (pin by tag; gemspec is "~> 0.9").
gem "recording_studio_trashable", github: "bowerbird-app/RecordingStudio_trashable", tag: "v0.9.0"
# Trashable's runtime deps are git-only; pin them for Bundler resolution.
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.208"
gem "recording_studio_metrics", github: "bowerbird-app/RecordingStudio_metrics", tag: "v0.2.0"

gem "devise"
gem "importmap-rails"
gem "pg"
gem "puma"
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
