# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class DenyAccessRequest < BaseService
      def initialize(request_recording:, manager_actor: nil, review_note: nil, controller: nil)
        @request_recording = request_recording
        @manager_actor = manager_actor
        @review_note = review_note
        @controller = controller
      end

      private

      def perform
        TransitionAccessRequest.call(
          request_recording: @request_recording,
          status: "denied",
          manager_actor: @manager_actor,
          review_note: @review_note,
          controller: @controller
        )
      end
    end
  end
end
