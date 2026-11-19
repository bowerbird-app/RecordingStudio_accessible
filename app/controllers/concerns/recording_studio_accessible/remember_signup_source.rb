# frozen_string_literal: true

module RecordingStudioAccessible
  module RememberSignupSource
    private

    def remember_signup_source(via:, recording_id:)
      return unless defined?(::RecordingStudioUser)
      return unless ::RecordingStudioUser.respond_to?(:remember_signup_source!)

      ::RecordingStudioUser.remember_signup_source!(
        request: request,
        source: { via: via, recording_id: recording_id }
      )
    end
  end
end
