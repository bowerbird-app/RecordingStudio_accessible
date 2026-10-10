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

      errors.add(:base, self.class.audience_write_error)
    end
  end
end
