# frozen_string_literal: true

module RecordingStudioAccessible
  module AccessRequestsHelper
    FRAME_ID = "access_request"
    MODAL = "modal"

    def access_request_modal(recording, role:, action: nil, label: nil)
      render "recording_studio_accessible/access_requests/modal",
             recording: recording,
             role: role,
             action: action,
             label: label.presence || accessible_t("requests.cta")
    end

    def access_request_frame_id
      FRAME_ID
    end

    def modal_presentation?
      params[:presentation].to_s == MODAL
    end

    def modal_frame_request?
      modal_presentation? && request.headers["Turbo-Frame"].to_s == FRAME_ID
    end

    def access_request_form_options
      return { data: { turbo_frame: access_request_frame_id } } if modal_frame_request?

      { local: true, data: { turbo: false } }
    end

    def access_request_modal_fields
      return unless modal_presentation?

      hidden_field_tag(:presentation, MODAL)
    end

    def access_request_page_path(recording, role:, action: nil)
      access_request_routes.new_recording_access_request_path(
        recording,
        role: role,
        access_action: action
      )
    end

    def access_request_modal_src(recording, role:, action:)
      access_request_routes.new_recording_access_request_path(
        recording,
        presentation: MODAL,
        role: role,
        access_action: action
      )
    end

    def access_request_status_style(status)
      { "pending" => :warning, "approved" => :success, "denied" => :danger }.fetch(status.to_s, :default)
    end

    def access_request_event_style(action)
      { "approved" => :success, "denied" => :danger, "withdrawn" => :default }.fetch(action.to_s, :warning)
    end

    private

    def access_request_routes
      respond_to?(:new_recording_access_request_path) ? self : recording_studio_accessible
    end
  end
end
