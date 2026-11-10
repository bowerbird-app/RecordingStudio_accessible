# frozen_string_literal: true

module RecordingStudioAccessible
  module AccessWriters
    def update_access(recording:, access_recording:, role:, manager_actor: nil, controller: nil)
      Services::UpdateRecordingAccess.call(
        recording: recording,
        access_recording: access_recording,
        role: role,
        manager_actor: manager_actor,
        controller: controller
      )
    end

    def revoke_access(recording:, access_recording:, manager_actor: nil, controller: nil)
      Services::RevokeRecordingAccess.call(
        recording: recording,
        access_recording: access_recording,
        manager_actor: manager_actor,
        controller: controller
      )
    end
  end
end
