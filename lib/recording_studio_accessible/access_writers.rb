# frozen_string_literal: true

module RecordingStudioAccessible
  module AccessWriters
    # Grant a role no higher than the manager's own access. Skips manage-access.
    def grant_self_delegated_access(recording:, actor:, role:, manager_actor: nil, depends_on: nil, source: :grant)
      Services::GrantRecordingAccess.call(
        recording: recording,
        actor: actor,
        role: role,
        manager_actor: manager_actor,
        depends_on: depends_on,
        source: source,
        authorization: :self_delegated
      )
    end

    def update_access(recording:, access_recording:, role:, manager_actor: nil, controller: nil,
                      allow_last_admin_removal: false)
      Services::UpdateRecordingAccess.call(
        recording: recording,
        access_recording: access_recording,
        role: role,
        manager_actor: manager_actor,
        controller: controller,
        allow_last_admin_removal: allow_last_admin_removal
      )
    end

    def revoke_access(recording:, access_recording:, manager_actor: nil, controller: nil,
                      allow_last_admin_removal: false)
      Services::RevokeRecordingAccess.call(
        recording: recording,
        access_recording: access_recording,
        manager_actor: manager_actor,
        controller: controller,
        allow_last_admin_removal: allow_last_admin_removal
      )
    end
  end
end
