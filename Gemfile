# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in recording_studio_accessible.gemspec
gemspec

gem "recording_studio", github: "bowerbird-app/RecordingStudio", tag: "v3.0.3"

gem "devise"
gem "importmap-rails"
gem "pg"
gem "puma"
gem "sprockets-rails"
gem "tailwindcss-rails"

group :development, :test do
  gem "bootsnap", require: false
  gem "debug"
  gem "simplecov", require: false
end

group :development do
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
end
