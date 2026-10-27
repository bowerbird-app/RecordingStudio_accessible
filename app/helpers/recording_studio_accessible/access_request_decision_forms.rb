# frozen_string_literal: true

module RecordingStudioAccessible
  module AccessRequestDecisionForms
    private

    def access_request_decision_form(request_recording, status, page, list_url)
      form_with(**access_request_decision_form_options(request_recording)) do
        safe_join(access_request_decision_form_parts(request_recording, status, page, list_url))
      end
    end

    def access_request_decision_form_options(request_recording)
      { url: access_request_transition_path(request_recording), method: :post, class: "grid gap-6",
        **access_request_form_options }
    end

    def access_request_decision_form_parts(request_recording, status, page, list_url)
      [
        access_request_list_return_fields(request_recording, status, page, list_url),
        access_request_decision_fields(request_recording, status),
        access_request_decision_submit(status)
      ]
    end

    def access_request_decision_fields(request_recording, status)
      record = request_recording.recordable
      return access_request_role_field(record, request_recording) if status == "approved"

      access_request_deny_field(record)
    end

    def access_request_role_field(record, request_recording)
      render FlatPack::RadioGroup::Component.new(**access_request_role_args(record, request_recording))
    end

    def access_request_role_args(record, request_recording)
      recording = request_recording.parent_recording
      {
        name: access_request_role_input_name(request_recording), variant: :inline, size: :sm, required: true,
        label: accessible_t("requests.approve_role"),
        options: access_request_approval_options(record, recording: recording),
        value: access_request_approval_default(record, recording: recording)
      }
    end

    def access_request_deny_field(record)
      render FlatPack::TextArea::Component.new(
        name: "review_note", label: accessible_t("requests.deny_note"), value: record.review_note, rows: 3
      )
    end

    def access_request_decision_submit(status)
      tag.div(class: "pt-6") do
        render FlatPack::Button::Component.new(
          text: access_request_decision_label(status), style: :primary, size: :md, type: "submit"
        )
      end
    end

    def access_request_list_return_fields(request_recording, status, page, list_url)
      prefix = "access-request-#{status}-#{request_recording.id}"
      safe_join([
                  hidden_field_tag(:return_to, "list", id: "#{prefix}-return-to"),
                  hidden_field_tag(:list_status, page.status, id: "#{prefix}-list-status"),
                  hidden_field_tag(:list_scope, access_request_list_scope(list_url), id: "#{prefix}-list-scope"),
                  hidden_field_tag(:status, status, id: "#{prefix}-status")
                ])
    end

    def access_request_role_input_name(request_recording)
      "role_#{request_recording.id}"
    end

    def access_request_list_scope(list_url)
      path = URI.parse(list_url.to_s).path.to_s.chomp("/")
      path == access_request_routes.access_requests_path.chomp("/") ? "collection" : "recording"
    rescue URI::InvalidURIError
      "recording"
    end

    def access_request_decision_label(status)
      accessible_t(status == "approved" ? "requests.approve" : "requests.deny")
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
