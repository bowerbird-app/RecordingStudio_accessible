# frozen_string_literal: true

require_relative "access_request_flow_helper"
require_relative "access_request_list_helper"

module RecordingStudioAccessible
  module AccessRequestsHelper
    include AccessRequestFlowHelper
    include AccessRequestListHelper

    FRAME_ID = "access_request"
    MODAL = "modal"

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

    def access_request_status_style(status)
      { "pending" => :warning, "approved" => :success, "denied" => :danger }.fetch(status.to_s, :default)
    end

    def access_request_event_style(action)
      { "approved" => :success, "denied" => :danger, "reopened" => :warning }.fetch(action.to_s, :warning)
    end

    def access_request_target_label
      AccessGrantedMailer.recordable_label_for(@recording).presence
    end

    def access_request_name_required?
      AccessRequestIntake.name_required?
    end

    def access_request_role_label(role)
      return accessible_t("requests.role_unset") if role.blank?

      accessible_role_name(role)
    end

    def access_request_approval_options(request_record)
      AccessRequestRoles.options_for(recording: @recording, action: request_record.action).map do |role|
        { value: role, label: accessible_role_name(role) }
      end
    end

    def access_request_approval_default(request_record)
      AccessRequestRoles.default_for(
        recording: @recording, action: request_record.action, suggested: request_record.role
      )
    end

    def access_request_event_description(event)
      note = event_note(event)
      email = event.actor.try(:email).to_s
      return email if note.blank?
      return note if email.blank?

      safe_join([note, email], " — ")
    end

    def access_request_person_label(actor)
      return if actor.blank?

      email = actor.try(:email).to_s
      name = requester_name(actor, email)
      return email if name.blank?

      safe_join([name, tag.div(email, class: muted_person_class)])
    end

    private

    def event_note(event)
      return unless %w[access_request_submitted resubmitted].include?(event.action.to_s)

      event.recordable.try(:message).to_s.strip.presence
    end

    def requester_name(actor, email)
      return unless defined?(::RecordingStudioUser) && RecordingStudioUser.respond_to?(:display_name_for)

      name = RecordingStudioUser.display_name_for(actor).to_s.strip
      name.presence unless name.casecmp?(email)
    end

    def muted_person_class
      "text-sm text-[var(--surface-muted-content-color)]"
    end

    def access_request_routes
      respond_to?(:new_recording_access_request_path) ? self : recording_studio_accessible
    end
  end
end
