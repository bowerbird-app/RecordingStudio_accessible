# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class RevokeRecordingAccess < BaseService
      include AccessRecordLifecycle

      def initialize(recording:, access_recording:, manager_actor: nil, controller: nil)
        @recording = recording
        @access_recording = access_recording
        @manager_actor = manager_actor
        @controller = controller
      end

      private

      def perform
        return failure("Recording is required") unless @recording
        return failure("Access recording is required") unless @access_recording

        authorization_result = authorize_access_management!(
          recording: @recording,
          manager_actor: manager_actor,
          controller: @controller
        )
        return authorization_result unless authorization_result == true
        return failure("Access recording is invalid") unless valid_access_recording_for_parent?(recording: @recording,
                                                                                                access_recording: @access_recording)

        ensure_current_impersonator_accessor!

        RecordingStudio::Recording.transaction do
          destroy_access_recording!(@access_recording, manager_actor: manager_actor)
        end

        success(true)
      rescue ActiveRecord::RecordInvalid => e
        failure(e.message, errors: e.record.errors.full_messages)
      rescue StandardError => e
        failure(e)
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
