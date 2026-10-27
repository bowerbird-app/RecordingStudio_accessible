# frozen_string_literal: true

require_relative "access_request_flow_helper"
require_relative "access_request_list_helper"
require_relative "access_request_show_helper"

module RecordingStudioAccessible
  module AccessRequestsHelper
    include AccessRequestFlowHelper
    include AccessRequestListHelper
    include AccessRequestShowHelper

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
      status.to_s == "pending" ? :primary : :default
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

    def access_request_approval_options(request_record, recording: @recording)
      AccessRequestRoles.options_for(
        recording: recording, action: request_record.action, manager: access_request_manager
      ).map do |role|
        { value: role, label: accessible_role_name(role), icon: access_request_role_icon(role) }
      end
    end

    def access_request_approval_default(request_record, recording: @recording)
      AccessRequestRoles.default_for(
        recording: recording, action: request_record.action, manager: access_request_manager,
        suggested: request_record.role.presence || "view"
      )
    end

    def access_request_person_label(actor)
      return if actor.blank?

      email = actor.try(:email).to_s.presence
      name = requester_name(actor, email)
      return name || email if name.blank? || email.blank?

      safe_join([tag.span(name, class: "font-medium"), tag.div(email, class: muted_person_class)])
    end

    private

    def access_request_manager
      RecordingStudioAccessible.configuration.current_actor_for(controller: controller)
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
