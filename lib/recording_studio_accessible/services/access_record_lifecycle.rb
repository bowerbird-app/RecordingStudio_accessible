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
        parent_recording = access_recording.parent_recording

        RecordingStudio.root_recording_or_self(parent_recording || access_recording).log_event(
          parent_recording || access_recording,
          action: "deleted",
          actor: manager_actor,
          metadata: { access_recording_id: access_recording.id, access_id: access_id }
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
        return unless Object.const_defined?(:Current)

        current = Object.const_get(:Current)
        return unless current.respond_to?(:attribute)

        current.attribute :impersonator unless impersonator_accessor_defined?(current)
        clear_stale_current_attributes_instance!(current)
      end

      def impersonator_accessor_defined?(current)
        return true if current.method_defined?(:impersonator)
        return false if current.is_a?(Module)

        current.respond_to?(:impersonator)
      end

      # CurrentAttributes stores instances by class name. Replacing the Current
      # constant can leave a stale same-named instance without new attributes.
      def clear_stale_current_attributes_instance!(current)
        return unless current.respond_to?(:instance)
        return if current.instance.is_a?(current)
        return unless current.respond_to?(:clear_all)

        current.clear_all
      end

      def reject_shared_root_target!(recording)
        return true unless RecordingStudioAccessible::SharedRootAccess.target?(recording)

        failure(RecordingStudioAccessible::SharedRootAccess::GRANT_DENIED_MESSAGE)
      end

      def validate_access_management_target!(recording, manager_actor:, controller: nil)
        authorization_result = authorize_access_management!(
          recording: recording,
          manager_actor: manager_actor,
          controller: controller
        )
        return authorization_result unless authorization_result == true

        shared_root_result = reject_shared_root_target!(recording)
        return shared_root_result unless shared_root_result == true
        return failure("Direct access is not enabled for this recording") unless access_management_allowed?(recording)

        true
      end

      def access_management_allowed?(recording)
        RecordingStudioAccessible::Compatibility.access_management_allowed?(recording)
      end
    end
  end
end
