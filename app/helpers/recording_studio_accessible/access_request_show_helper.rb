# frozen_string_literal: true

module RecordingStudioAccessible
  module AccessRequestShowHelper
    ROLE_ICONS = {
      "view" => "eye",
      "edit" => "pencil",
      "admin" => "shield-check"
    }.freeze

    def access_request_show_heading(request_record)
      accessible_t(
        "requests.show_heading",
        name: access_request_actor_name(request_record.actor),
        recording: access_request_target_label
      )
    end

    def access_request_actor_name(actor)
      return if actor.blank?

      email = actor.try(:email).to_s.presence
      requester_name(actor, email).presence || email
    end

    def access_request_requested_on(request_recording)
      l(request_recording.created_at.to_date, format: :long)
    end

    def access_request_decision_tab(request_record)
      request_record.status == "denied" ? 1 : 0
    end

    def access_request_role_icon(role)
      ROLE_ICONS.fetch(role.to_s, "user")
    end

    # SegmentedButtons renders each button with #call, so icon: has no view to draw.
    def access_request_role_button_text(option)
      icon = render(FlatPack::Shared::IconComponent.new(name: access_request_role_icon(option[:value]), size: :sm))
      tag.span(safe_join([icon, option[:label]]), class: "inline-flex items-center gap-2")
    end
  end
end
