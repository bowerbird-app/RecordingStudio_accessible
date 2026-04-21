# frozen_string_literal: true

require "recording_studio"
require "recording_studio_accessible/version"
require "recording_studio_accessible/hooks"
require "recording_studio_accessible/configuration"
require "recording_studio_accessible/compatibility"
require "recording_studio_accessible/services/base_service"

RecordingStudioAccessible::Compatibility.missing_constant_paths.each do |path|
  require path
end

require "recording_studio_accessible/engine"

module RecordingStudioAccessible
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end
  end
end
