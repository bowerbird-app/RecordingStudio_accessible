# frozen_string_literal: true

module RecordingStudioAccessible
  # Root ids where authorized?(actor:, recording: root, role:) is true.
  # One id column, so callers can pass it to where. A nil actor or an
  # unranked role is Recording.none. A custom authorization service that
  # does not implement the query raises instead of returning a set.
  module RootIdsApi
    def authorized_root_recording_ids(actor:, role: :view)
      Authorization.authorized_root_recording_ids(actor: actor, role: role)
    end

    def authorized_root_recording_ids_supported?
      Authorization.authorized_root_recording_ids_supported?
    end
  end
end
