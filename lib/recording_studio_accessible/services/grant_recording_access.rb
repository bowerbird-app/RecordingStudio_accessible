# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class GrantRecordingAccess < BaseService
      include AccessRecordLifecycle
      include AccessGrantWriter

      def initialize(recording:, actor:, role:, manager_actor: nil, controller: nil, depends_on: nil)
        @recording = recording
        @actor = actor
        @role = role.to_s
        @manager_actor = manager_actor
        @controller = controller
        @depends_on = depends_on
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

        dependency_result = validate_dependent_grant
        return dependency_result unless dependency_result == true

        true
      end

      def validate_dependent_grant
        manager = @depends_on || existing_manager_recording
        return true if manager.nil?

        error = RecordingStudioAccessible::DependentAccess.grant_error(
          target_recording: @recording,
          role: @role,
          depends_on: manager,
          dependent_recording: existing_access_recordings.first
        )
        return true unless error

        failure(error)
      end

      def existing_manager_recording
        existing = existing_access_recordings.first
        return unless existing

        RecordingStudioAccessible::DependentAccess.manager_recording_for(existing)
      end

      def service_args
        {
          recording_id: @recording&.id,
          actor_gid: global_id_string_for(@actor),
          role: @role,
          manager_actor_gid: global_id_string_for(manager_actor),
          depends_on_recording_id: @depends_on.respond_to?(:id) ? @depends_on.id : nil
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
