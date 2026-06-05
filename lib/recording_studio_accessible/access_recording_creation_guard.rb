# frozen_string_literal: true

require "active_support/concern"

module RecordingStudioAccessible
  module AccessRecordingCreationGuard
    extend ActiveSupport::Concern

    included do
      validate :prevent_unsupported_access_recording_creation, on: :create
    end

    private

    def prevent_unsupported_access_recording_creation
      return unless access_recordable?
      return unless access_placement_enabled?
      return if RecordingStudioAccessible::AccessCreationContext.allowed?

      errors.add(:base, "Create access grants through RecordingStudioAccessible.grant_access")
    end

    def access_recordable?
      return true if recordable_type == "RecordingStudio::Access"
      return false unless defined?(::RecordingStudio::Access)
      return true if recordable.is_a?(::RecordingStudio::Access)

      association(:recordable).target.is_a?(::RecordingStudio::Access)
    end

    def access_placement_enabled?
      return false if parent_recording.blank?
      return true if RecordingStudioAccessible::Compatibility.access_parent_allowed?(parent_recording)

      errors.add(:parent_recording, "does not allow RecordingStudio::Access children")
      false
    end
  end
end
