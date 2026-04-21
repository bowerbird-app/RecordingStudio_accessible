# frozen_string_literal: true

require "recording_studio"
require "recording_studio_accessible/version"
require "recording_studio_accessible/hooks"
require "recording_studio_accessible/configuration"
require "recording_studio_accessible/compatibility"
require "recording_studio_accessible/services/base_service"

unless RecordingStudioAccessible::Compatibility.core_access_present?
  require "recording_studio_accessible/extracted/recording_studio/access"
  require "recording_studio_accessible/extracted/recording_studio/access_boundary"
  require "recording_studio_accessible/extracted/recording_studio/services/access_check_class_methods"
  require "recording_studio_accessible/extracted/recording_studio/services/access_check"
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
