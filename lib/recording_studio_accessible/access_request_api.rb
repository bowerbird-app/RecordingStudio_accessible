# frozen_string_literal: true

module RecordingStudioAccessible
  module AccessRequestApi
    def request_access(recording:, actor:, role: nil, action: nil, message: nil, controller: nil)
      Services::RequestAccess.call(
        recording: recording,
        actor: actor,
        role: role,
        action: action,
        message: message,
        controller: controller
      )
    end

    def transition_access_request(request_recording:, status:, manager_actor: nil, role: nil, review_note: nil,
                                  controller: nil)
      Services::TransitionAccessRequest.call(
        request_recording: request_recording,
        status: status,
        manager_actor: manager_actor,
        role: role,
        review_note: review_note,
        controller: controller
      )
    end

    def approve_access_request(request_recording:, manager_actor: nil, role: nil, controller: nil)
      transition_access_request(
        request_recording: request_recording,
        status: "approved",
        manager_actor: manager_actor,
        role: role,
        controller: controller
      )
    end

    def deny_access_request(request_recording:, manager_actor: nil, review_note: nil, controller: nil)
      transition_access_request(
        request_recording: request_recording,
        status: "denied",
        manager_actor: manager_actor,
        review_note: review_note,
        controller: controller
      )
    end
  end
end
