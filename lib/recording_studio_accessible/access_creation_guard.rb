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

      # ActiveModel 8.1 ignores message: when the type is a String, so pass the
      # translated string as the type/message.
      errors.add(
        :base,
        Copy.t("errors.create_via_grant_access")
      )
    end
  end
end
