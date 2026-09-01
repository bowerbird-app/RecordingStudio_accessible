# frozen_string_literal: true

module RecordingStudioAccessible
  # Enqueue dependent-grant voiding when an Access recording is revised,
  # trashed, or destroyed. Authorize still fail-closes if this job lags.
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

      RecordingStudioAccessible::VoidDependentAccessesJob.perform_later(id)
    rescue StandardError
      nil
    end

    def recording_studio_accessible_access_recording?
      recordable_type == "RecordingStudio::Access"
    end
  end
end
