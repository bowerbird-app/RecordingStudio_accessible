# frozen_string_literal: true

module RecordingStudioAccessible
  class ApplicationController < (defined?(::ApplicationController) ? ::ApplicationController : ActionController::Base)
    helper RecordingStudioAccessible::ApplicationHelper

    recording_studio_layout { RecordingStudioAccessible.configuration.layout }

    private

    def refuse_access_grant(error, template: nil, location: nil)
      @grant_refused = error
      store_grant_refused_cta(error, now: template.present?)
      if template
        flash.now[:alert] = error.message
        render template, status: :unprocessable_entity
      else
        redirect_to(location || "/", alert: error.message)
      end
    end

    def store_grant_refused_cta(error, now:)
      bag = now ? flash.now : flash
      bag[:grant_refused_cta_path] = error.cta_path
      bag[:grant_refused_cta_label] = error.cta_label
    end
  end
end
