# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class GrantRecordingAccess < BaseService
      include AccessRecordLifecycle

      def initialize(recording:, actor:, role:, manager_actor: nil)
        @recording = recording
        @actor = actor
        @role = role.to_s
        @manager_actor = manager_actor
      end

      private

      def perform
        return failure("Recording is required") unless @recording

        authorization_result = authorize_access_management!(recording: @recording, manager_actor: @manager_actor)
        return authorization_result unless authorization_result == true
        return failure("Direct access is not enabled for this recording") unless access_enabled?
        return failure("Role is invalid") unless valid_role?

        access_recording = nil
        ensure_current_impersonator_accessor!

        RecordingStudio::Recording.transaction do
          lock_grant_scope!

          existing_recordings = existing_access_recordings.to_a
          access_recording = existing_recordings.first

          if access_recording
            deduplicate_access_recordings!(existing_recordings.drop(1))

            root_recording.revise(access_recording, actor: @manager_actor) do |access|
              access.role = @role
            end
          else
            access_recording = root_recording.record(
              RecordingStudio::Access,
              actor: @manager_actor,
              parent_recording: @recording
            ) do |access|
              access.actor = @actor
              access.role = @role
            end
          end
        end

        success(access_recording)
      rescue ActiveRecord::RecordInvalid => e
        failure(e.message, errors: e.record.errors.full_messages)
      rescue StandardError => e
        failure(e)
      end

      def service_args
        {
          recording_id: @recording&.id,
          actor_gid: @actor&.to_global_id&.to_s,
          role: @role,
          manager_actor_gid: @manager_actor&.to_global_id&.to_s
        }
      end

      def valid_role?
        RecordingStudio::Access.roles.key?(@role)
      end

      def access_enabled?
        RecordingStudioAccessible::PlacementPolicy.allowed_child_on_recording?(recording: @recording,
                                                                               child_type: :access)
      end

      def root_recording
        @recording.root_recording || @recording
      end

      def lock_grant_scope!
        @recording.lock!
      end

      def existing_access_recordings
        return unless @actor

        RecordingStudioAccessible::DirectAccessQuery.access_recordings_for_actor(recording: @recording, actor: @actor)
      end

      def deduplicate_access_recordings!(access_recordings)
        access_recordings.each do |access_recording|
          destroy_access_recording!(access_recording, manager_actor: @manager_actor)
        end
      end
    end
  end
end
