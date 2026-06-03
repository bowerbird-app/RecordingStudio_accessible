# frozen_string_literal: true

require "active_support/concern"

module RecordingStudioAccessible
  module AccessCreationGuard
    extend ActiveSupport::Concern

    included do
      validate :prevent_unsupported_direct_creation, on: :create
    end

    private

    def prevent_unsupported_direct_creation
      return if RecordingStudioAccessible::AccessCreationContext.allowed?

      errors.add(:base, "Create access grants through RecordingStudioAccessible.grant_access")
    end
  end
end
