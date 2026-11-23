# frozen_string_literal: true

module RecordingStudioAccessible
  module McpCopy
    # Human copy for the four access tools. No View, Edit, or Admin names.
    module Copy
      TYPE = {
        description: "Public name of the recording. For example, Workspace."
      }.freeze
      ID = {
        description: "Recording id."
      }.freeze

      RECORDING = {
        "type" => TYPE,
        "id" => ID
      }.freeze

      TITLES = {
        "list_access" => "List who can use this recording",
        "grant_access" => "Grant someone this recording",
        "update_access" => "Change a direct grant",
        "revoke_access" => "Remove a direct grant"
      }.freeze

      DESCRIPTIONS = {
        "list_access" =>
          "Lists the people who can use this recording, including pending email invitations, so you can see " \
          "them before you change anything. The recording must already exist. Direct grants must be enabled " \
          "on it. This call does not change a grant or an invitation. Inherited grants are changed on the " \
          "source recording. A missing recording is rejected. Returns grants.",
        "grant_access" =>
          "Writes a direct grant so one person can use this recording. The recording must already exist, and " \
          "direct grants must be enabled. Pass actor_id from list_access or the host's people lookup, or pass " \
          "email to invite. Do not pass both. If that email already belongs to an account, the grant is " \
          "written now. Otherwise an invitation is stored and sent. A second call for the same person revises " \
          "the existing direct grant. It does not change an inherited grant. A name this recording does not " \
          "accept is rejected. Returns the grant, or the pending invitation.",
        "update_access" =>
          "Changes the stored name on a direct grant. The recording must already exist, and direct grants " \
          "must be enabled. Pass actor_id from list_access and the new role. It does not change an inherited " \
          "grant or a pending invitation. Changing the last person who can manage grants on this recording " \
          "is rejected. If the grant already has that name, the call succeeds and nothing changes. Returns " \
          "the updated grant.",
        "revoke_access" =>
          "Removes a direct grant so that person no longer has it here. The recording must already exist, " \
          "and direct grants must be enabled. Pass actor_id from list_access. It does not change an " \
          "inherited grant, and it does not cancel a pending invitation. Removing the last person who can " \
          "manage grants on this recording is rejected. Returns revoked true and the person who was removed."
      }.freeze

      INPUTS = {
        "list_access" => RECORDING,
        "grant_access" => RECORDING,
        "update_access" => RECORDING,
        "revoke_access" => RECORDING
      }.freeze

      OUTPUTS = {
        "list_access" => "grants on this recording",
        "grant_access" => "the grant or the pending invitation",
        "update_access" => "the updated direct grant",
        "revoke_access" => "the removed grant"
      }.freeze
    end
  end
end
