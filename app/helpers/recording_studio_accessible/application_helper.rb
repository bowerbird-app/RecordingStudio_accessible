# frozen_string_literal: true

module RecordingStudioAccessible
  module ApplicationHelper
    def recording_studio_accessible_flash_style(level)
      case level.to_s
      when "notice"
        :success
      when "alert"
        :danger
      else
        :info
      end
    end
  end
end
