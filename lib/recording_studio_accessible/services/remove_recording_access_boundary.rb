# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class RemoveRecordingAccessBoundary < BaseService
      include AccessRecordLifecycle

      def initialize(recording:, boundary_recording:, manager_actor: nil)
        @recording = recording
        @boundary_recording = boundary_recording
        @manager_actor = manager_actor
      end

      private

      def perform
        return failure("Recording is required") unless @recording
        return failure("Boundary recording is required") unless @boundary_recording

        authorization_result = authorize_access_management!(recording: @recording, manager_actor: @manager_actor)
        return authorization_result unless authorization_result == true
        return failure("Boundary recording is invalid") unless valid_boundary_recording_for_parent?

        ensure_current_impersonator_accessor!

        RecordingStudio::Recording.transaction do
          destroy_boundary_recording!
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
          boundary_recording_id: @boundary_recording&.id,
          manager_actor_gid: @manager_actor&.to_global_id&.to_s
        }
      end

      def valid_boundary_recording_for_parent?
        @boundary_recording.parent_recording_id == @recording.id &&
          @boundary_recording.recordable_type == "RecordingStudio::AccessBoundary"
      end

      def destroy_boundary_recording!
        boundary_id = @boundary_recording.recordable_id

        @boundary_recording.root_recording.hard_delete(@boundary_recording, actor: @manager_actor)
        RecordingStudio::AccessBoundary.where(id: boundary_id).delete_all if orphaned_boundary_id?(boundary_id)
      end

      def orphaned_boundary_id?(boundary_id)
        RecordingStudio::Recording.unscoped.where(recordable_type: "RecordingStudio::AccessBoundary",
                                                  recordable_id: boundary_id).none?
      end
    end
  end
end