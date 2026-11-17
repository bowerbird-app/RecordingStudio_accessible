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
        summary: RecordingStudioAccessible::Api::OpenapiCopy::LIST_ACCESS_SUMMARY,
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
            "The id of an existing person to grant. Take it from list_access results or the host's people " \
            "lookup. Required together with actor_type when you are not inviting by email. Do not pass this " \
            "with email."
        },
        actor_type: {
          type: :string,
          allow_blank: false,
          description:
            "The type of that person, for example User. When granting by actor_id, leave it out to default " \
            "to User when User is allowed, matching update_access and revoke_access. An unknown or " \
            "disallowed type is rejected."
        },
        email: {
          type: :string,
          allow_blank: false,
          description:
            "The email to invite when you are not naming an existing person by actor_id. Take the address " \
            "from the person you want to invite. Do not pass this with actor_id. The address is stored in " \
            "lowercase. If the host can resolve it to an existing account, the grant is written immediately. " \
            "Otherwise an invitation is stored and sent. A second invite to the same open address updates " \
            "the role and resends."
        },
        role: {
          type: :string,
          required: true,
          allow_blank: false,
          description:
            "The role to give this person. #{RecordingStudioAccessible::Api::OpenapiCopy::DEFAULT_ROLE} " \
            "An unrecognized role is rejected. If this person already has a direct grant on this recording, " \
            "this call revises that grant to the new role. A role above what the caller may assign is rejected."
        }
      },
      openapi: {
        summary: RecordingStudioAccessible::Api::OpenapiCopy::GRANT_ACCESS_SUMMARY,
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
          description:
            "The id of the person whose direct grant to change. Take it from list_access results or the " \
            "host's people lookup."
        },
        actor_type: {
          type: :string,
          allow_blank: false,
          description:
            "The type of that person, for example User. Leave it out to default to User when User is " \
            "allowed, matching revoke_access and grant_access. An unknown or disallowed type is rejected."
        },
        role: {
          type: :string,
          required: true,
          allow_blank: false,
          description:
            "The new role for this direct grant. " \
            "#{RecordingStudioAccessible::Api::OpenapiCopy::DEFAULT_ROLE} An unrecognized role is rejected. " \
            "A role above what the caller may assign is rejected."
        }
      },
      openapi: {
        summary: RecordingStudioAccessible::Api::OpenapiCopy::UPDATE_ACCESS_SUMMARY,
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
          description:
            "The id of the person whose direct grant to remove. Take it from list_access results or the " \
            "host's people lookup."
        },
        actor_type: {
          type: :string,
          allow_blank: false,
          description:
            "The type of that person, for example User. Leave it out to default to User when User is " \
            "allowed, matching update_access and grant_access. An unknown or disallowed type is rejected."
        }
      },
      openapi: {
        summary: RecordingStudioAccessible::Api::OpenapiCopy::REVOKE_ACCESS_SUMMARY,
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
