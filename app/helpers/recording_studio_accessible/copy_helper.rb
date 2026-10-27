# frozen_string_literal: true

module RecordingStudioAccessible
  module CopyHelper
    def accessible_t(...)
      Copy.t(...)
    end

    def accessible_copy(override, key, **)
      Copy.value(override, key, **)
    end

    def accessible_role_name(role)
      Copy.role_name(role)
    end

    def accessible_invitation_state(state)
      Copy.invitation_state(state)
    end
  end
end
