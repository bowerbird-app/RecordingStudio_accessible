# frozen_string_literal: true

module RecordingStudioAccessible
  module Api
    # HTTP OpenAPI prose. MCP tool wording lives in McpCopy::Copy.
    module OpenapiCopy
      LIST_ACCESS_TITLE = "List access"
      GRANT_ACCESS_TITLE = "Grant access"
      UPDATE_ACCESS_TITLE = "Update a direct grant"
      REVOKE_ACCESS_TITLE = "Revoke a direct grant"

      LIST_ACCESS_SUMMARY = "Return grants and email invitations for one recording."
      GRANT_ACCESS_SUMMARY = "Store a direct grant, or an invitation for an email address."
      UPDATE_ACCESS_SUMMARY = "Replace the role stored on one direct grant."
      REVOKE_ACCESS_SUMMARY = "Delete one direct grant from this recording."

      LIST_ACCESS = [
        "Member POST with no JSON body.",
        "The path selects the recording, and direct access has to be on.",
        "The 200 JSON is an object whose grants array mixes two row shapes.",
        "A grant row carries actor, role, inherited, effective_role, source_recording, and status granted.",
        "An invitation row carries email, role, source_recording, and status pending or expired.",
        "The array includes grants stored here, grants inherited from a parent, and open or expired invitations.",
        "Nothing is written.",
        "To change an inherited grant, call the recording named by source_recording.",
        "A path that does not resolve, or a recording with direct access off, is 404."
      ].join(" ").freeze

      GRANT_ACCESS = [
        "Member POST.",
        "The path selects the recording, and direct access has to be on.",
        "The JSON body identifies one person with actor_id and an optional actor_type, or an email to invite.",
        "role is always required.",
        "A body that sends actor_id and email together is rejected.",
        "An omitted actor_type defaults to User when that type is allowed.",
        "An email the host can resolve is stored as a grant immediately.",
        "Any other email is stored as an invitation and mailed.",
        "Repeating the request for the same person replaces the role on the direct grant already stored here.",
        "A grant inherited from a parent is left on that parent.",
        "Unknown people, unknown role names, and a disallowed actor_type are rejected.",
        "A role the caller may not assign is rejected.",
        "The 200 JSON is the direct grant when access is stored: invited false, role, actor, source_recording, notice.",
        "When only an email is stored, the 200 JSON is the invitation: invited true, email, role, notice."
      ].join(" ").freeze

      UPDATE_ACCESS = [
        "Member POST.",
        "The path selects the recording, and direct access has to be on.",
        "The JSON body is actor_id, role, and an optional actor_type.",
        "An omitted actor_type defaults to User when that type is allowed.",
        "role replaces the value stored on that person's direct grant.",
        "Inherited grants and open invitations are outside this action.",
        "Unknown people, unknown role names, a disallowed actor_type, and a missing direct grant are rejected.",
        "A role the caller may not assign is rejected.",
        "So is a change that would leave the recording with nobody who can manage grants.",
        "When the stored role already matches the body, the response is still 200 and the grant is unchanged.",
        "The 200 JSON is that direct grant.",
        "Its fields are invited false, inherited false, role, effective_role, actor, and source_recording."
      ].join(" ").freeze

      REVOKE_ACCESS = [
        "Member POST.",
        "The path selects the recording, and direct access has to be on.",
        "The JSON body is actor_id and an optional actor_type.",
        "An omitted actor_type defaults to User when that type is allowed.",
        "The matching direct grant is deleted.",
        "Inherited grants stay on their parent, and open invitations stay stored.",
        "Unknown people, a disallowed actor_type, a missing direct grant, and an inherited grant are rejected.",
        "A delete that would leave the recording with nobody who can manage grants is rejected.",
        "The 200 JSON is revoked true plus the actor that was removed."
      ].join(" ").freeze

      ACTOR_ID_GRANT =
        "Identifier of an existing person. Required when the body does not include email. " \
        "Leave it out when inviting by email."
      ACTOR_TYPE =
        "Type name for that person, such as User. When omitted on an actor_id request, defaults to User " \
        "if User is allowed. An unknown or disallowed type is rejected."
      EMAIL =
        "Address to invite when the body does not include actor_id. Stored in lowercase. A resolvable " \
        "account is stored as a grant immediately. Otherwise an invitation is stored and mailed. Repeating " \
        "an open address replaces the role and mails the invitation again."
      ROLE_GRANT =
        "Role name to store. A type may declare names of its own. An unknown name is rejected. A name the " \
        "caller may not assign is rejected. When a direct grant already exists, this request replaces its role."
      ACTOR_ID_UPDATE = "Identifier of the person whose direct grant should change."
      ROLE_UPDATE =
        "Replacement role name. A type may declare names of its own. An unknown name is rejected. A name " \
        "the caller may not assign is rejected."
      ACTOR_ID_REVOKE = "Identifier of the person whose direct grant should be deleted."

      LIST_OK = "JSON object with a grants array of grant rows and invitation rows."
      GRANT_OK = "JSON for the stored direct grant, or for the stored invitation."
      UPDATE_OK = "JSON for the direct grant after the role is replaced."
      REVOKE_OK = "JSON with revoked true and the removed actor."
      FORBIDDEN = "The caller cannot manage access on this recording."
      MISSING = "The recording is missing, or direct access is off."
      GRANT_INVALID = "The JSON body cannot be stored as a grant or an invitation."
      UPDATE_INVALID = "The JSON body cannot be applied to a direct grant."
      REVOKE_INVALID = "The JSON body cannot delete a direct grant."
    end
  end
end
