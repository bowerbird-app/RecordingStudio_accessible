# frozen_string_literal: true

require "active_support/concern"

module RecordingStudioAccessible
  module AudienceCreationGuard
    extend ActiveSupport::Concern

    included do
      validate :prevent_unsupported_direct_audience_creation, on: :create
    end

    private

    def prevent_unsupported_direct_audience_creation
      return if RecordingStudioAccessible::AudienceWriteContext.allowed?

      # audience_write_error already resolves through Copy.t / RecordingStudio.t.
      # ActiveModel 8.1 ignores message: for String types, so pass it directly.
      errors.add(:base, self.class.audience_write_error)
    end
  end
end
