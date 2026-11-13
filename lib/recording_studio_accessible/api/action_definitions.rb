# frozen_string_literal: true

module RecordingStudioAccessible
  module Api
    GRANT_ACCESS_DESCRIPTION = OpenapiCopy::GRANT_ACCESS
    LIST_ACCESS_DESCRIPTION = OpenapiCopy::LIST_ACCESS
    REVOKE_ACCESS_DESCRIPTION = OpenapiCopy::REVOKE_ACCESS
    UPDATE_ACCESS_DESCRIPTION = OpenapiCopy::UPDATE_ACCESS
  end
end

RecordingStudioAccessible::Api.const_set(
  :ACTION_DEFINITIONS,
  {
    list_access: {
      handler: RecordingStudioAccessible::Api::ListAccess,
      fields: {},
      openapi: {
        summary: "List access",
        description: RecordingStudioAccessible::Api::LIST_ACCESS_DESCRIPTION,
        responses: {
          "200" => {
            description: "Grants and pending invitations on this recording.",
            content: {
              "application/json" => {
                schema: {
                  type: "object",
                  required: %w[grants],
                  properties: {
                    grants: {
                      type: "array",
                      items: {
                        oneOf: [
                          RecordingStudioAccessible::Api::OpenapiSchemas::GRANT_ROW,
                          RecordingStudioAccessible::Api::OpenapiSchemas::INVITATION_ROW
                        ]
                      }
                    }
                  }
                }
              }
            }
          },
          "403" => { description: "Not allowed to manage access." },
          "404" => { description: "Direct access is not enabled for this recording." }
        }
      }
    },
    grant_access: {
      handler: RecordingStudioAccessible::Api::GrantAccess,
      fields: {
        actor_id: {
          type: :string,
          allow_blank: false,
          description:
            "The id of an existing person to grant. Required together with actor_type when you are not " \
            "inviting by email. Do not pass this with email."
        },
        actor_type: {
          type: :string,
          allow_blank: false,
          description:
            "The type of that person, for example User. When granting by actor_id, leave it out to default " \
            "to User when User is allowed, matching update_access and revoke_access. The type must be one " \
            "the host allows you to grant."
        },
        email: {
          type: :string,
          allow_blank: false,
          description:
            "An email to invite when you are not naming an existing person by actor_id. Do not pass this " \
            "with actor_id. The address is stored in lowercase. If the host can resolve it to an existing " \
            "account, the grant is written immediately. Otherwise an invitation is stored and sent. A second " \
            "invite to the same open address updates the role and resends."
        },
        role: {
          type: :string,
          required: true,
          allow_blank: false,
          description:
            "Required. The role to give this person. #{RecordingStudioAccessible::Api::OpenapiCopy::DEFAULT_ROLE} " \
            "An unrecognized role is rejected. If this person already has a direct grant on this recording, " \
            "this call revises that grant to the new role. You cannot grant a role higher than the one you hold."
        }
      },
      openapi: {
        summary: "Grant access",
        description: RecordingStudioAccessible::Api::GRANT_ACCESS_DESCRIPTION,
        responses: {
          "200" => {
            description:
              "Access granted or invitation stored. A second grant revises the existing direct grant. " \
              "A known email is granted immediately.",
            content: {
              "application/json" => {
                schema: {
                  oneOf: [
                    RecordingStudioAccessible::Api::OpenapiSchemas::DIRECT_GRANT,
                    RecordingStudioAccessible::Api::OpenapiSchemas::PENDING_INVITATION
                  ]
                }
              }
            }
          },
          "403" => { description: "Not allowed to manage access." },
          "404" => { description: "Direct access is not enabled for this recording." },
          "422" => { description: "Grant request is invalid." }
        }
      }
    },
    update_access: {
      handler: RecordingStudioAccessible::Api::UpdateAccess,
      fields: {
        actor_id: {
          type: :string,
          required: true,
          allow_blank: false,
          description: "The id of the person whose direct grant to change. Required."
        },
        actor_type: {
          type: :string,
          allow_blank: false,
          description:
            "The type of that person, for example User. Leave it out to default to User when User is " \
            "allowed, matching revoke_access and grant_access. The type must be one the host allows."
        },
        role: {
          type: :string,
          required: true,
          allow_blank: false,
          description:
            "The new role for this direct grant. Required. " \
            "#{RecordingStudioAccessible::Api::OpenapiCopy::DEFAULT_ROLE} You can only assign a role you " \
            "already hold, or a weaker one, unless you are an admin."
        }
      },
      openapi: {
        summary: "Update access",
        description: RecordingStudioAccessible::Api::UPDATE_ACCESS_DESCRIPTION,
        responses: {
          "200" => {
            description: "Direct grant updated.",
            content: {
              "application/json" => {
                schema: RecordingStudioAccessible::Api::OpenapiSchemas::UPDATE_ACCESS
              }
            }
          },
          "403" => { description: "Not allowed to manage access." },
          "404" => { description: "Direct access is not enabled for this recording." },
          "422" => { description: "Update request is invalid." }
        }
      }
    },
    revoke_access: {
      handler: RecordingStudioAccessible::Api::RevokeAccess,
      fields: {
        actor_id: {
          type: :string,
          required: true,
          allow_blank: false,
          description: "The id of the person whose direct grant to remove. Required."
        },
        actor_type: {
          type: :string,
          allow_blank: false,
          description:
            "The type of that person, for example User. Leave it out to default to User when User is " \
            "allowed, matching update_access and grant_access. The type must be one the host allows."
        }
      },
      openapi: {
        summary: "Revoke access",
        description: RecordingStudioAccessible::Api::REVOKE_ACCESS_DESCRIPTION,
        responses: {
          "200" => {
            description: "Direct grant removed.",
            content: {
              "application/json" => {
                schema: RecordingStudioAccessible::Api::OpenapiSchemas::REVOKE_ACCESS
              }
            }
          },
          "403" => { description: "Not allowed to manage access." },
          "404" => { description: "Direct access is not enabled for this recording." },
          "422" => { description: "Revoke request is invalid." }
        }
      }
    }
  }.freeze
)
