# frozen_string_literal: true

require "active_support/concern"

module RecordingStudioAccessible
  module AccessCreationGuard
    extend ActiveSupport::Concern

    included do
      before_create :prevent_unsupported_direct_creation
    end

    private

    def prevent_unsupported_direct_creation
      return if RecordingStudioAccessible::AccessCreationContext.allowed?

      errors.add(:base, "Create access grants through RecordingStudioAccessible.grant_access")
      throw :abort
    end
  end
end
