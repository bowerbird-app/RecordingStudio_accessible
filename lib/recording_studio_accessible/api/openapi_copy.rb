# frozen_string_literal: true

module RecordingStudioAccessible
  module Api
    module OpenapiCopy
      DEFAULT_ROLE =
        "Default roles: #{RecordingStudioAccessible::RoleSet::DEFAULT_NAMES.join(', ')}. " \
        "Types may declare others.".freeze

      GRANT_ACCESS_SUMMARY =
        "Give a role on this recording to a known person, or invite an email."

      GRANT_ACCESS =
        "A direct grant is a role stored on this recording for one person. Granting it lets that person " \
        "work here. The recording must already exist. Direct access must be enabled on it. Pass actor_id " \
        "as the person's id from list_access results or the host's people lookup, with actor_type when it " \
        "is not User. Or pass email as the address to invite. Do not pass actor_id together with email. A " \
        "missing actor_type defaults to User when User is allowed. If that email already belongs to an " \
        "account the host can resolve, the grant is written immediately. Otherwise an invitation is stored " \
        "and sent. If the person already has a direct grant on this recording, this call revises that grant " \
        "to the new role. It does not change an inherited grant from a parent. Re-inviting an open email " \
        "updates the role and resends the invitation. A missing person is rejected as not found. An " \
        "unrecognized role is rejected. An unknown or disallowed actor_type is rejected. actor_id together " \
        "with email is rejected. A role above what the caller may assign is rejected. Returns a direct " \
        "grant (invited false, role, actor, source_recording, notice) when access is written, or a pending " \
        "invitation (invited true, email, role, notice) when an email is stored."

      LIST_ACCESS_SUMMARY =
        "Show who has access to this recording, including pending email invitations."

      LIST_ACCESS =
        "Lists the people with a role on this recording so you can see grants before you change them. " \
        "Rows include direct grants, inherited grants from a parent, and pending or expired email " \
        "invitations. The recording must already exist. Direct access must be enabled on it. This call " \
        "does not change any grant or invitation. Inherited grants cannot be changed here. Change them " \
        "on the source recording. A recording that does not exist, or one without direct access, is " \
        "rejected as not found. Returns grants, an array of grant rows (actor, role, inherited, " \
        "effective_role, source_recording, status granted) and invitation rows (email, role, " \
        "source_recording, status pending or expired)."

      REVOKE_ACCESS_SUMMARY =
        "Remove a direct grant from this recording."

      REVOKE_ACCESS =
        "A direct grant is a role stored on this recording for one person. Revoking it removes that grant " \
        "so they no longer have that role here. It does not change an inherited grant from a parent, and " \
        "it does not cancel a pending invitation. The recording must already exist. Direct access must " \
        "be enabled on it. Pass actor_id as the person's id from list_access results or the host's people " \
        "lookup. A missing actor_type defaults to User when User is allowed. A missing person is rejected " \
        "as not found. An unknown or disallowed actor_type is rejected. An inherited grant is rejected. " \
        "A missing direct grant is rejected. Removing the last admin is rejected. Returns revoked true " \
        "and the actor that was removed."

      UPDATE_ACCESS_SUMMARY =
        "Change the role of a direct grant on this recording."

      UPDATE_ACCESS =
        "A direct grant is a role stored on this recording for one person. Updating it changes that " \
        "stored role. It does not change an inherited grant from a parent, and it does not change a " \
        "pending invitation. The recording must already exist. Direct access must be enabled on it. " \
        "Pass actor_id as the person's id from list_access results or the host's people lookup. Pass " \
        "role as the new role. A missing actor_type defaults to User when User is allowed. A missing " \
        "person is rejected as not found. An unrecognized role is rejected. An unknown or disallowed " \
        "actor_type is rejected. An inherited grant is rejected. A missing direct grant is rejected. " \
        "Changing the last admin down from admin is rejected. A role above what the caller may assign " \
        "is rejected. If the grant already has that role, the call succeeds and nothing changes. Returns " \
        "the updated direct grant (invited false, inherited false, role, effective_role, actor, " \
        "source_recording)."
    end
  end
end
