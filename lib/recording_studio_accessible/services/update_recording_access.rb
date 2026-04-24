# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class UpdateRecordingAccess < BaseService
      include AccessRecordLifecycle

      def initialize(recording:, access_recording:, role:, manager_actor: nil)
        @recording = recording
        @access_recording = access_recording
        @role = role.to_s
        @manager_actor = manager_actor
      end

      private

      def perform
        return failure("Recording is required") unless @recording
        return failure("Access recording is required") unless @access_recording

        authorization_result = authorize_access_management!(recording: @recording, manager_actor: @manager_actor)
        return authorization_result unless authorization_result == true
        return failure("Access recording is invalid") unless valid_access_recording_for_parent?(recording: @recording,
                                                                                                access_recording: @access_recording)
        return failure("Role is invalid") unless valid_role?

        ensure_current_impersonator_accessor!

        revised_recording = @access_recording.root_recording.revise(@access_recording,
                                                                    actor: @manager_actor) do |access|
          access.role = @role
        end

        success(revised_recording)
      rescue ActiveRecord::RecordInvalid => e
        failure(e.message, errors: e.record.errors.full_messages)
      rescue StandardError => e
        failure(e)
      end

      def service_args
        {
          recording_id: @recording&.id,
          access_recording_id: @access_recording&.id,
          role: @role,
          manager_actor_gid: @manager_actor&.to_global_id&.to_s
        }
      end

      def valid_role?
        RecordingStudio::Access.roles.key?(@role)
      end
    end
  end
end
