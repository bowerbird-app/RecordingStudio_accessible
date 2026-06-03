# frozen_string_literal: true

require "active_support/concern"

module RecordingStudioAccessible
  module AccessRecordingCreationGuard
    extend ActiveSupport::Concern

    included do
      before_create :prevent_unsupported_access_recording_creation
    end

    private

    def prevent_unsupported_access_recording_creation
      return unless access_recordable?
      return if RecordingStudioAccessible::AccessCreationContext.allowed?

      errors.add(:base, "Create access grants through RecordingStudioAccessible.grant_access")
      throw :abort
    end

    def access_recordable?
      recordable_type == "RecordingStudio::Access" ||
        (defined?(::RecordingStudio::Access) && recordable.is_a?(::RecordingStudio::Access))
    end
  end
end
