# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class GrantRecordingAccess < BaseService
      include AccessRecordLifecycle
      include AccessGrantWriter

      def initialize(recording:, actor:, role:, manager_actor: nil, controller: nil)
        @recording = recording
        @actor = actor
        @role = role.to_s
        @manager_actor = manager_actor
        @controller = controller
      end

      private

      def perform
        validation_result = validate_request
        return validation_result unless validation_result == true

        ensure_current_impersonator_accessor!

        access_recording = upsert_access_recording!
        success(access_recording)
      rescue ActiveRecord::RecordInvalid => e
        failure(e.message, errors: e.record.errors.full_messages)
      rescue StandardError => e
        failure(e)
      end

      def validate_request
        return failure("Recording is required") unless @recording
        return failure("Actor is required") unless @actor

        access_validation = validate_access_management_target!(
          @recording,
          manager_actor: manager_actor,
          controller: @controller
        )
        return access_validation unless access_validation == true
        return failure("Actor type is not allowed for access") unless allowed_access_actor_type?
        return failure("Role is invalid") unless RecordingStudio::Access.roles.key?(@role)

        true
      end

      def service_args
        {
          recording_id: @recording&.id,
          actor_gid: global_id_string_for(@actor),
          role: @role,
          manager_actor_gid: global_id_string_for(manager_actor)
        }
      end

      def manager_actor
        @manager_actor ||= effective_manager_actor(manager_actor: @manager_actor, controller: @controller)
      end

      def allowed_access_actor_type?
        RecordingStudioAccessible.configuration.allowed_access_actor_type?(@actor)
      end
    end
  end
end
