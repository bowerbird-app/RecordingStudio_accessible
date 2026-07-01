# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    module AccessRecordLifecycle
      private

      def authorize_access_management!(recording:, manager_actor:, controller: nil)
        return true if RecordingStudioAccessible::AccessManagementPolicy.allowed?(
          recording: recording,
          actor: effective_manager_actor(manager_actor: manager_actor, controller: controller),
          controller: controller
        )

        failure("Not authorized to manage access")
      end

      def effective_manager_actor(manager_actor:, controller: nil)
        manager_actor || RecordingStudioAccessible.configuration.current_actor_for(controller: controller)
      end

      def valid_access_recording_for_parent?(recording:, access_recording:)
        access_recording.parent_recording_id == recording.id &&
          access_recording.recordable_type == "RecordingStudio::Access" &&
          same_root?(recording, access_recording) &&
          active_recording?(access_recording)
      end

      def destroy_access_recording!(access_recording, manager_actor:)
        access_id = access_recording.recordable_id

        RecordingStudio.root_recording_or_self(access_recording).log_event(
          access_recording,
          action: "deleted",
          actor: manager_actor
        )
        access_recording.destroy!
        RecordingStudio::Access.where(id: access_id).delete_all if orphaned_access_id?(access_id)
      end

      def orphaned_access_id?(access_id)
        RecordingStudio::Recording.unscoped.where(recordable_type: "RecordingStudio::Access",
                                                  recordable_id: access_id).none?
      end

      def same_root?(recording, access_recording)
        RecordingStudio.root_recording_id_for(recording) == RecordingStudio.root_recording_id_for(access_recording)
      end

      def active_recording?(recording)
        return true unless recording.respond_to?(:trashed_at)

        recording.trashed_at.nil?
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
