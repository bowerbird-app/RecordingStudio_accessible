# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class UpdateRecordingAccess < BaseService
      include AccessRecordLifecycle

      def initialize(recording:, access_recording:, role:, manager_actor: nil, controller: nil,
                     allow_last_admin_removal: false)
        @recording = recording
        @access_recording = access_recording
        @role = role.to_s.strip
        @manager_actor = manager_actor
        @controller = controller
        @allow_last_admin_removal = allow_last_admin_removal
      end

      private

      def perform
        validation_result = validate_update_request
        return validation_result unless validation_result == true

        ensure_current_impersonator_accessor!

        revised_recording = LastAdminGuard.protect!(
          recordings: last_admin_recordings,
          allow_last_admin_removal: @allow_last_admin_removal
        ) do
          RecordingStudioAccessible::AccessCreationContext.allow do
            RecordingStudio.root_recording_or_self(@access_recording).revise(@access_recording,
                                                                             actor: manager_actor) do |access|
              access.role = @role
            end
          end
        end

        success(revised_recording)
      rescue ::RecordingStudioAccessible::LastAdminError => e
        failure(e, errors: [e])
      rescue ActiveRecord::RecordInvalid => e
        failure(e.message, errors: e.record.errors.full_messages)
      rescue StandardError => e
        unexpected_failure(e)
      end

      def last_admin_recordings
        [@recording] + LastAdminGuard.dependent_parent_recordings(@access_recording)
      end

      def validate_update_request
        return failure(copy("errors.recording_required")) unless @recording
        return failure(copy("errors.access_recording_required")) unless @access_recording

        access_validation = validate_access_management_target!(
          @recording,
          manager_actor: manager_actor,
          controller: @controller
        )
        return access_validation unless access_validation == true
        return failure(copy("errors.access_recording_invalid")) unless valid_access_recording_for_parent?(recording: @recording,
                                                                                                          access_recording: @access_recording)
        return failure(copy("errors.role_invalid")) unless valid_role?
        return failure(copy("errors.role_exceeds_manager")) unless role_within_manager?

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
        RecordingStudioAccessible.role_valid_for?(@recording, @role)
      end

      def role_within_manager?
        RoleCeiling.allowed?(recording: @recording, manager: manager_actor, role: @role)
      end
    end
  end
end
