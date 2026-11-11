# frozen_string_literal: true

module RecordingStudioAccessible
  class ApplicationController < (defined?(::ApplicationController) ? ::ApplicationController : ActionController::Base)
    helper RecordingStudioAccessible::ApplicationHelper

    recording_studio_layout { RecordingStudioAccessible.configuration.layout }

    private

    def refuse_access_grant(error, template: nil, location: nil)
      target = error.redirect_to
      if target.present?
        redirect_to(target, alert: error.message, allow_other_host: absolute_http_url?(target))
      elsif template
        flash.now[:alert] = error.message
        render template, status: :unprocessable_entity
      else
        redirect_to(location || "/", alert: error.message)
      end
    end

    def absolute_http_url?(target)
      target.to_s.match?(%r{\Ahttps?://}i)
    end
  end
end
