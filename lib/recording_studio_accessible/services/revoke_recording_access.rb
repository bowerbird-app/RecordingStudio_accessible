# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class RevokeRecordingAccess < BaseService
      def initialize(recording:, access_recording:, manager_actor: nil)
        @recording = recording
        @access_recording = access_recording
        @manager_actor = manager_actor
      end

      private

      def perform
        return failure("Recording is required") unless @recording
        return failure("Access recording is required") unless @access_recording
        return failure("Access recording is invalid") unless valid_access_recording?

        access_id = @access_recording.recordable_id
        ensure_current_impersonator_accessor!

        RecordingStudio::Recording.transaction do
          @access_recording.root_recording.hard_delete(@access_recording, actor: @manager_actor)
          RecordingStudio::Access.where(id: access_id).delete_all if orphaned_access_id?(access_id)
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
          manager_actor_gid: @manager_actor&.to_global_id&.to_s
        }
      end

      def valid_access_recording?
        @access_recording.parent_recording_id == @recording.id &&
          @access_recording.recordable_type == "RecordingStudio::Access"
      end

      def orphaned_access_id?(access_id)
        RecordingStudio::Recording.unscoped.where(recordable_type: "RecordingStudio::Access",
                                                  recordable_id: access_id).none?
      end

      def ensure_current_impersonator_accessor!
        return unless defined?(Current)
        return unless Current.respond_to?(:attribute)
        return if Current.respond_to?(:impersonator)

        Current.attribute :impersonator
      end
    end
  end
end
