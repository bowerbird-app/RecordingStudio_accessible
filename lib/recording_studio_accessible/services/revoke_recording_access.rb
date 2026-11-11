# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class RevokeRecordingAccess < BaseService
      include AccessRecordLifecycle

      def initialize(recording:, access_recording:, manager_actor: nil, controller: nil,
                     allow_last_admin_removal: false)
        @recording = recording
        @access_recording = access_recording
        @manager_actor = manager_actor
        @controller = controller
        @allow_last_admin_removal = allow_last_admin_removal
      end

      private

      def perform
        return failure(copy("errors.recording_required")) unless @recording
        return failure(copy("errors.access_recording_required")) unless @access_recording

        authorization_result = authorize_access_management!(
          recording: @recording,
          manager_actor: manager_actor,
          controller: @controller
        )
        return authorization_result unless authorization_result == true
        return failure(copy("errors.access_recording_invalid")) unless revocable_access_recording?(recording: @recording,
                                                                                                   access_recording: @access_recording)

        ensure_current_impersonator_accessor!

        LastAdminGuard.protect!(
          recordings: last_admin_recordings,
          allow_last_admin_removal: @allow_last_admin_removal
        ) do
          destroy_access_recording!(@access_recording, manager_actor: manager_actor)
        end

        success(true)
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

      def service_args
        {
          recording_id: @recording&.id,
          access_recording_id: @access_recording&.id,
          manager_actor_gid: global_id_string_for(manager_actor)
        }
      end

      def manager_actor
        @manager_actor ||= effective_manager_actor(manager_actor: @manager_actor, controller: @controller)
      end
    end
  end
end
