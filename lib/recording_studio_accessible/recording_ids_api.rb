# frozen_string_literal: true

module RecordingStudioAccessible
  # Recording ids under one root where authorized?(actor:, recording:, role:)
  # is true. One id column, so callers can pass it to where. A nil actor, a
  # root that is not a recording, or an unranked role is Recording.none.
  # A custom authorization service that does not implement the query raises
  # instead of returning a set.
  module RecordingIdsApi
    def authorized_recording_ids(actor:, root:, role: :view, recordable_type: nil)
      Authorization.authorized_recording_ids(
        actor: actor,
        root: root,
        role: role,
        recordable_type: recordable_type
      )
    end

    def authorized_recording_ids_supported?
      Authorization.authorized_recording_ids_supported?
    end
  end
end
