# frozen_string_literal: true

module RecordingStudioAccessible
  module Authorization
    class << self
      def role_for(actor:, recording:)
        authorization_service.role_for(actor: actor, recording: recording)
      end

      def allowed?(actor:, recording:, role:)
        authorization_service.allowed?(actor: actor, recording: recording, role: role)
      end
      alias authorized? allowed?

      def allowed_through?(actor:, through:, recording:, role:, controller: nil)
        authorization_service.allowed_through?(
          actor: actor,
          through: through,
          recording: recording,
          role: role,
          controller: controller
        )
      end
      alias authorized_through? allowed_through?

      def role_through(actor:, through:, recording:, controller: nil)
        authorization_service.role_through(
          actor: actor,
          through: through,
          recording: recording,
          controller: controller
        )
      end

      def root_recordings_for(actor:, minimum_role: nil)
        authorization_service.root_recordings_for(actor: actor, minimum_role: minimum_role)
      end

      def root_recording_ids_for(actor:, minimum_role: nil)
        authorization_service.root_recording_ids_for(actor: actor, minimum_role: minimum_role)
      end

      def access_recordings_for(recording)
        authorization_service.access_recordings_for(recording)
      end

      def access_recordings_for_actor(recording:, actor:)
        authorization_service.access_recordings_for_actor(recording: recording, actor: actor)
      end

      private

      def authorization_service
        RecordingStudioAccessible::AuthorizationService
      end
    end
  end
end
