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

      create_via_grant_access_error =
        "Create access grants through RecordingStudioAccessible.grant_access"
      errors.add(
        :base,
        create_via_grant_access_error,
        message: Copy.t("errors.create_via_grant_access", default: create_via_grant_access_error)
      )
    end
  end
end
