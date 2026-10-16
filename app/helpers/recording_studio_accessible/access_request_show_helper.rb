# frozen_string_literal: true

module RecordingStudioAccessible
  module AccessRequestShowHelper
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

    def access_request_requested_on(request_recording, events)
      l(access_request_requested_at(request_recording, events).to_date, format: :long)
    end

    def access_request_decision_tab(request_record)
      request_record.status == "denied" ? 1 : 0
    end

    private

    def access_request_requested_at(request_recording, events)
      submitted = Array(events).find { |event| event.action.to_s == RecordingStudio::AccessRequest::EVENT_SUBMITTED }
      submitted&.occurred_at || request_recording.created_at
    end
  end
end
