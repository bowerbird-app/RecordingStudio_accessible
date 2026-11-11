# frozen_string_literal: true

module RecordingStudioAccessible
  module Api
    ACTION_DEFINITIONS = {
      list_access: {
        handler: ListAccess,
        fields: {},
        openapi: {
          summary: "List access",
          description: "Lists direct and inherited grants on this recording.",
          responses: {
            "200" => { description: "Grants on this recording." },
            "403" => { description: "Not allowed to manage access." },
            "404" => { description: "Direct access is not enabled for this recording." }
          }
        }
      },
      grant_access: {
        handler: GrantAccess,
        fields: {
          actor_id: { type: :string, allow_blank: false },
          actor_type: { type: :string, allow_blank: false },
          email: { type: :string, allow_blank: false },
          role: {
            type: :string,
            required: true,
            allow_blank: false,
            enum: RecordingStudioAccessible::RoleSet::DEFAULT_NAMES
          }
        },
        openapi: {
          summary: "Grant access",
          description: "Grants a role to an actor id plus actor_type, or invites an email.",
          responses: {
            "200" => { description: "Access granted or invitation stored." },
            "403" => { description: "Not allowed to manage access." },
            "404" => { description: "Direct access is not enabled for this recording." },
            "422" => { description: "Grant request is invalid." }
          }
        }
      },
      update_access: {
        handler: UpdateAccess,
        fields: {
          actor_id: { type: :string, required: true, allow_blank: false },
          actor_type: { type: :string, allow_blank: false },
          role: { type: :string, required: true, allow_blank: false }
        },
        openapi: {
          summary: "Update access",
          description: "Changes the role of a direct grant on this recording.",
          responses: {
            "200" => { description: "Direct grant updated." },
            "403" => { description: "Not allowed to manage access." },
            "404" => { description: "Direct access is not enabled for this recording." },
            "422" => { description: "Update request is invalid." }
          }
        }
      },
      revoke_access: {
        handler: RevokeAccess,
        fields: {
          actor_id: { type: :string, required: true, allow_blank: false },
          actor_type: { type: :string, allow_blank: false }
        },
        openapi: {
          summary: "Revoke access",
          description: "Removes a direct grant from this recording.",
          responses: {
            "200" => { description: "Direct grant removed." },
            "403" => { description: "Not allowed to manage access." },
            "404" => { description: "Direct access is not enabled for this recording." },
            "422" => { description: "Revoke request is invalid." }
          }
        }
      }
    }.freeze
  end
end
