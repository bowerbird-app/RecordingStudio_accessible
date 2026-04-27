# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class CreateRecordingAccessBoundary < BaseService
      include AccessRecordLifecycle

      def initialize(recording:, minimum_role:, manager_actor: nil)
        @recording = recording
        @minimum_role = minimum_role.to_s
        @manager_actor = manager_actor
      end

      private

      def perform
        return failure("Recording is required") unless @recording

        authorization_result = authorize_access_management!(recording: @recording, manager_actor: @manager_actor)
        return authorization_result unless authorization_result == true
        return failure("Boundary is not enabled for this recording") unless boundary_enabled?
        return failure("Minimum role is invalid") unless valid_minimum_role?

        boundary_recording = nil
        ensure_current_impersonator_accessor!

        RecordingStudio::Recording.transaction do
          lock_boundary_scope!

          boundary_recording = existing_boundary_recording
          next if boundary_recording

          boundary_recording = root_recording.record(
            RecordingStudio::AccessBoundary,
            actor: @manager_actor,
            parent_recording: @recording
          ) do |boundary|
            boundary.minimum_role = @minimum_role
          end
        end

        success(boundary_recording)
      rescue ActiveRecord::RecordInvalid => e
        failure(e.message, errors: e.record.errors.full_messages)
      rescue StandardError => e
        failure(e)
      end

      def service_args
        {
          recording_id: @recording&.id,
          minimum_role: @minimum_role,
          manager_actor_gid: @manager_actor&.to_global_id&.to_s
        }
      end

      def boundary_enabled?
        RecordingStudioAccessible::PlacementPolicy.allowed_child_on_recording?(recording: @recording,
                                                                               child_type: :boundary)
      end

      def valid_minimum_role?
        RecordingStudio::AccessBoundary.minimum_roles.key?(@minimum_role)
      end

      def root_recording
        @recording.root_recording || @recording
      end

      def lock_boundary_scope!
        @recording.lock!
      end

      def existing_boundary_recording
        RecordingStudio::Recording.unscoped.find_by(
          parent_recording_id: @recording.id,
          recordable_type: "RecordingStudio::AccessBoundary",
          trashed_at: nil
        )
      end
    end
  end
end