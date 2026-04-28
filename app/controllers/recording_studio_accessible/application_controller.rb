# frozen_string_literal: true

module RecordingStudioAccessible
  class ApplicationController < (defined?(::ApplicationController) ? ::ApplicationController : ActionController::Base)
    helper RecordingStudioAccessible::ApplicationHelper
  end
end
