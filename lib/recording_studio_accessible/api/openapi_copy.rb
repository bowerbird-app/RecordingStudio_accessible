# frozen_string_literal: true

module RecordingStudioAccessible
  module Api
    module OpenapiCopy
      DEFAULT_ROLE =
        "Default roles: #{RecordingStudioAccessible::RoleSet::DEFAULT_NAMES.join(', ')}. " \
        "Types may declare others.".freeze

      GRANT_ACCESS =
        "Gives a role on this recording to a person you already know, or invites an email. " \
        "Name the person as actor_id plus actor_type, or pass email, not both. " \
        "A missing actor_type defaults to User when User is allowed. " \
        "If that email already belongs to an account the host can resolve, the grant is written immediately. " \
        "Otherwise an invitation is stored and sent. " \
        "If the person already has a direct grant on this recording, this call revises that grant to the new role. " \
        "It does not change an inherited grant from a parent. You cannot grant a role higher than the one you hold. " \
        "The recording must already exist, and direct access must be enabled on it."

      LIST_ACCESS =
        "Lists direct and inherited grants, plus pending or expired email invitations, on this recording. " \
        "Inherited grants come from a parent and cannot be changed here. " \
        "This does not change any grant or invitation. " \
        "The recording must already exist, and direct access must be enabled on it."

      REVOKE_ACCESS =
        "Removes a direct grant from this recording. " \
        "It does not change an inherited grant from a parent, and it does not cancel a pending invitation. " \
        "You cannot remove the last admin. " \
        "The recording must already exist, and direct access must be enabled on it."

      UPDATE_ACCESS =
        "Changes the role of a direct grant on this recording. " \
        "It does not change an inherited grant from a parent, and it does not change a pending invitation. " \
        "You cannot change the last admin down from admin. " \
        "You can only assign a role you already hold, or a weaker one, unless you are an admin. " \
        "The recording must already exist, and direct access must be enabled on it."
    end
  end
end
