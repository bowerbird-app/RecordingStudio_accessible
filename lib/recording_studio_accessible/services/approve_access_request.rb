# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class ApproveAccessRequest < BaseService
      def initialize(request_recording:, manager_actor: nil, role: nil, controller: nil)
        @request_recording = request_recording
        @manager_actor = manager_actor
        @role = role
        @controller = controller
      end

      private

      def perform
        TransitionAccessRequest.call(
          request_recording: @request_recording,
          status: "approved",
          manager_actor: @manager_actor,
          role: @role,
          controller: @controller
        )
      end
    end
  end
end
