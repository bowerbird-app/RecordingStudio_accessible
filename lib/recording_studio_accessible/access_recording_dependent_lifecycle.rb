# frozen_string_literal: true

module RecordingStudioAccessible
  # Enqueue dependent-grant voiding when an Access recording is revised,
  # trashed, destroyed, or moved. Authorize still fail-closes if this job lags
  # for trash, destroy, off-root, or a weaker manager role.
  #
  # Moveable's `move_to!` persists a parent (and, on cross-root, root) change
  # on the Recording. This hook watches that lifecycle rather than adding a
  # second ACL. Dependents are voided in place and do not follow the move.
  module AccessRecordingDependentLifecycle
    extend ActiveSupport::Concern

    included do
      after_update :recording_studio_accessible_enqueue_void_dependents
      after_destroy :recording_studio_accessible_enqueue_void_dependents
    end

    private

    def recording_studio_accessible_enqueue_void_dependents
      return unless recording_studio_accessible_access_recording?
      return if id.blank?
      return unless RecordingStudioAccessible::DependentAccess.column_available?

      if recording_studio_accessible_access_moved?
        RecordingStudioAccessible::VoidDependentAccessesJob.perform_later(id, moved: true)
      else
        RecordingStudioAccessible::VoidDependentAccessesJob.perform_later(id)
      end
    rescue StandardError
      nil
    end

    def recording_studio_accessible_access_moved?
      return false unless respond_to?(:saved_change_to_attribute?)

      saved_change_to_attribute?(:parent_recording_id) || saved_change_to_attribute?(:root_recording_id)
    end

    def recording_studio_accessible_access_recording?
      recordable_type == "RecordingStudio::Access"
    end
  end
end
