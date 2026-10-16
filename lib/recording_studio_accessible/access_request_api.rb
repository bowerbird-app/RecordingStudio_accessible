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

    def approve_access_request(request_recording:, manager_actor: nil, role: nil, controller: nil)
      Services::ApproveAccessRequest.call(
        request_recording: request_recording,
        manager_actor: manager_actor,
        role: role,
        controller: controller
      )
    end

    def deny_access_request(request_recording:, manager_actor: nil, review_note: nil, controller: nil)
      Services::DenyAccessRequest.call(
        request_recording: request_recording,
        manager_actor: manager_actor,
        review_note: review_note,
        controller: controller
      )
    end

    def withdraw_access_request(request_recording:, actor: nil, controller: nil)
      Services::WithdrawAccessRequest.call(
        request_recording: request_recording,
        actor: actor,
        controller: controller
      )
    end
  end
end
