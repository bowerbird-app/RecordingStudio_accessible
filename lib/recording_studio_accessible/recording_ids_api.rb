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

    # Recordings under one root that authorized? would allow. Unloaded, so the
    # caller can order, keyset, and limit. scope defaults to every recording.
    # A custom service that does not implement the query raises.
    def authorized_recordings(actor:, root:, scope: nil, role: :view, recordable_type: nil)
      Authorization.authorized_recordings(
        actor: actor,
        root: root,
        scope: scope,
        role: role,
        recordable_type: recordable_type
      )
    end

    def authorized_recordings_supported?
      Authorization.authorized_recordings_supported?
    end
  end
end
