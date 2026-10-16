# frozen_string_literal: true

module RecordingStudioAccessible
  module AccessRequestMenuForms
    private

    def access_request_menu_forms(request_recording)
      safe_join(access_request_transition_forms(request_recording))
    end

    def access_request_transition_forms(request_recording)
      AccessRequestTransitions.targets_for(request_recording.recordable.status).flat_map do |status|
        access_request_forms_for(request_recording, status)
      end
    end

    def access_request_forms_for(request_recording, status)
      return access_request_approve_forms(request_recording) if status == "approved"

      [access_request_transition_form(request_recording, status)]
    end

    def access_request_approve_forms(request_recording)
      access_request_role_options(request_recording).map do |role|
        access_request_transition_form(request_recording, "approved", role)
      end
    end

    def access_request_transition_form(request_recording, status, role = nil)
      form_with(url: access_request_transition_path(request_recording), method: :post, local: true,
                html: { id: access_request_form_id(request_recording, status, role), class: "hidden" }) do
        safe_join([hidden_field_tag(:status, status), role && hidden_field_tag(:role, role)].compact)
      end
    end

    def access_request_manager
      RecordingStudioAccessible.configuration.current_actor_for(controller: controller)
    end

    def access_request_role_options(request_recording)
      record = request_recording.recordable
      AccessRequestRoles.options_for(
        recording: request_recording.parent_recording, action: record.action, manager: access_request_manager
      )
    end

    def access_request_form_id(request_recording, status, role = nil)
      ["access-request", request_recording.id, status, role].compact.join("-")
    end

    def access_request_transition_path(request_recording)
      access_request_routes.transition_recording_access_request_path(
        request_recording.parent_recording, request_recording
      )
    end

    def access_request_review_path(request_recording)
      access_request_routes.recording_access_request_path(
        request_recording.parent_recording, request_recording
      )
    end

    def access_request_cursor_marker(request_recording)
      tag.span(nil, hidden: true, data: { pagination_cursor: AccessRequestIndex.cursor_for(request_recording) })
    end
  end
end
