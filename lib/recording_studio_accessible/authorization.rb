# frozen_string_literal: true

module RecordingStudioAccessible
  module Authorization
    class << self
      def role_for(actor:, recording:)
        service = authorization_service
        return nil unless service

        service.role_for(actor: actor, recording: recording)
      end

      def allowed?(actor:, recording:, role:)
        service = authorization_service
        return false unless service

        service.allowed?(actor: actor, recording: recording, role: role)
      end
      alias authorized? allowed?

      private

      def authorization_service
        RecordingStudioAccessible::Compatibility.authorization_service
      end
    end
  end
end
