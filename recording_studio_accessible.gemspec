# frozen_string_literal: true

require_relative "lib/recording_studio_accessible/version"

Gem::Specification.new do |spec|
  spec.name        = "recording_studio_accessible"
  spec.version     = RecordingStudioAccessible::VERSION
  spec.authors     = ["Bowerbird"]
  spec.homepage    = "https://github.com/bowerbird-app/RecordingStudio_accessible"
  spec.summary     = "Optional access-control addon for RecordingStudio"
  spec.description = "Extracted access-control models, authorization service, install generators, and demo app wiring for RecordingStudio hosts"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", "~> 8.1.0"
  spec.add_dependency "recording_studio", ">= 0.1.0"
end
