# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    module AccessRecordLifecycle
      private

      def authorize_access_management!(recording:, manager_actor:)
        return true if RecordingStudioAccessible::AccessManagementPolicy.allowed?(
          recording: recording,
          actor: manager_actor
        )

        failure("Not authorized to manage access")
      end

      def valid_access_recording_for_parent?(recording:, access_recording:)
        access_recording.parent_recording_id == recording.id &&
          access_recording.recordable_type == "RecordingStudio::Access"
      end

      def destroy_access_recording!(access_recording, manager_actor:)
        access_id = access_recording.recordable_id

        access_recording.root_recording.hard_delete(access_recording, actor: manager_actor)
        RecordingStudio::Access.where(id: access_id).delete_all if orphaned_access_id?(access_id)
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
