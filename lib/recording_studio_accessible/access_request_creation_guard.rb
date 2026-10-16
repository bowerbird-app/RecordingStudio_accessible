# frozen_string_literal: true

require "active_support/concern"

module RecordingStudioAccessible
  module AccessRequestCreationGuard
    extend ActiveSupport::Concern

    included do
      validate :prevent_unsupported_direct_creation, on: :create
    end

    private

    def prevent_unsupported_direct_creation
      return if RecordingStudioAccessible::AccessRequestCreationContext.allowed?

      errors.add(:base, Copy.t("errors.create_via_request_access"))
    end
  end
end
