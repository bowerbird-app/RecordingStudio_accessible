# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in recording_studio_accessible.gemspec
gemspec

gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v4.7.0"
# Query-only trash helpers (pin by tag; gemspec is "~> 0.10"). require: false so
# Bundler does not auto-load the Trashable engine; lib requires .../query.
gem "recording_studio_trashable", github: "bowerbird-app/RecordingStudio_trashable",
                                  tag: "v0.11.0", require: false
# Trashable's gemspec deps are git-only; pin them for Bundler resolution only.
gem "flat_pack", github: "bowerbird-app/flatpack", tag: "v0.1.208", require: false
gem "recording_studio_metrics", github: "bowerbird-app/RecordingStudio_metrics", tag: "v0.2.0",
                                require: false

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
