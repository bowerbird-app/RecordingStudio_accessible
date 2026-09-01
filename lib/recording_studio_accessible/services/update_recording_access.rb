# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class UpdateRecordingAccess < BaseService
      include AccessRecordLifecycle

      def initialize(recording:, access_recording:, role:, manager_actor: nil, controller: nil)
        @recording = recording
        @access_recording = access_recording
        @role = role.to_s
        @manager_actor = manager_actor
        @controller = controller
      end

      private

      def perform
        validation_result = validate_update_request
        return validation_result unless validation_result == true

        ensure_current_impersonator_accessor!

        revised_recording = RecordingStudioAccessible::AccessCreationContext.allow do
          RecordingStudio.root_recording_or_self(@access_recording).revise(@access_recording,
                                                                           actor: manager_actor) do |access|
            access.role = @role
          end
        end

        success(revised_recording)
      rescue ActiveRecord::RecordInvalid => e
        failure(e.message, errors: e.record.errors.full_messages)
      rescue StandardError => e
        failure(e)
      end

      def validate_update_request
        return failure("Recording is required") unless @recording
        return failure("Access recording is required") unless @access_recording

        access_validation = validate_access_management_target!(
          @recording,
          manager_actor: manager_actor,
          controller: @controller
        )
        return access_validation unless access_validation == true
        return failure("Access recording is invalid") unless valid_access_recording_for_parent?(recording: @recording,
                                                                                                access_recording: @access_recording)
        return failure("Role is invalid") unless valid_role?

        dependency_result = validate_dependent_grant
        return dependency_result unless dependency_result == true

        true
      end

      def validate_dependent_grant
        manager = RecordingStudioAccessible::DependentAccess.manager_recording_for(@access_recording)
        return true if manager.nil?

        error = RecordingStudioAccessible::DependentAccess.grant_error(
          target_recording: @recording,
          role: @role,
          depends_on: manager,
          dependent_recording: @access_recording
        )
        return true unless error

        failure(error)
      end

      def service_args
        {
          recording_id: @recording&.id,
          access_recording_id: @access_recording&.id,
          role: @role,
          manager_actor_gid: global_id_string_for(manager_actor)
        }
      end

      def manager_actor
        @manager_actor ||= effective_manager_actor(manager_actor: @manager_actor, controller: @controller)
      end

      def valid_role?
        RecordingStudio::Access.roles.key?(@role)
      end
    end
  end
end
