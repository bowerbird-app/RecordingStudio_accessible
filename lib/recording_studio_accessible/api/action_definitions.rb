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
        title: RecordingStudioAccessible::Api::OpenapiCopy::LIST_ACCESS_TITLE,
        summary: RecordingStudioAccessible::Api::OpenapiCopy::LIST_ACCESS_SUMMARY,
        description: RecordingStudioAccessible::Api::LIST_ACCESS_DESCRIPTION,
        responses: {
          "200" => {
            description: RecordingStudioAccessible::Api::OpenapiCopy::LIST_OK,
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
          "403" => { description: RecordingStudioAccessible::Api::OpenapiCopy::FORBIDDEN },
          "404" => { description: RecordingStudioAccessible::Api::OpenapiCopy::MISSING }
        }
      }
    },
    grant_access: {
      handler: RecordingStudioAccessible::Api::GrantAccess,
      fields: {
        actor_id: {
          type: :string,
          allow_blank: false,
          description: RecordingStudioAccessible::Api::OpenapiCopy::ACTOR_ID_GRANT
        },
        actor_type: {
          type: :string,
          allow_blank: false,
          description: RecordingStudioAccessible::Api::OpenapiCopy::ACTOR_TYPE
        },
        email: {
          type: :string,
          allow_blank: false,
          description: RecordingStudioAccessible::Api::OpenapiCopy::EMAIL
        },
        role: {
          type: :string,
          required: true,
          allow_blank: false,
          description: RecordingStudioAccessible::Api::OpenapiCopy::ROLE_GRANT
        }
      },
      openapi: {
        title: RecordingStudioAccessible::Api::OpenapiCopy::GRANT_ACCESS_TITLE,
        summary: RecordingStudioAccessible::Api::OpenapiCopy::GRANT_ACCESS_SUMMARY,
        description: RecordingStudioAccessible::Api::GRANT_ACCESS_DESCRIPTION,
        responses: {
          "200" => {
            description: RecordingStudioAccessible::Api::OpenapiCopy::GRANT_OK,
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
          "403" => { description: RecordingStudioAccessible::Api::OpenapiCopy::FORBIDDEN },
          "404" => { description: RecordingStudioAccessible::Api::OpenapiCopy::MISSING },
          "422" => { description: RecordingStudioAccessible::Api::OpenapiCopy::GRANT_INVALID }
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
          description: RecordingStudioAccessible::Api::OpenapiCopy::ACTOR_ID_UPDATE
        },
        actor_type: {
          type: :string,
          allow_blank: false,
          description: RecordingStudioAccessible::Api::OpenapiCopy::ACTOR_TYPE
        },
        role: {
          type: :string,
          required: true,
          allow_blank: false,
          description: RecordingStudioAccessible::Api::OpenapiCopy::ROLE_UPDATE
        }
      },
      openapi: {
        title: RecordingStudioAccessible::Api::OpenapiCopy::UPDATE_ACCESS_TITLE,
        summary: RecordingStudioAccessible::Api::OpenapiCopy::UPDATE_ACCESS_SUMMARY,
        description: RecordingStudioAccessible::Api::UPDATE_ACCESS_DESCRIPTION,
        responses: {
          "200" => {
            description: RecordingStudioAccessible::Api::OpenapiCopy::UPDATE_OK,
            content: {
              "application/json" => {
                schema: RecordingStudioAccessible::Api::OpenapiSchemas::UPDATE_ACCESS
              }
            }
          },
          "403" => { description: RecordingStudioAccessible::Api::OpenapiCopy::FORBIDDEN },
          "404" => { description: RecordingStudioAccessible::Api::OpenapiCopy::MISSING },
          "422" => { description: RecordingStudioAccessible::Api::OpenapiCopy::UPDATE_INVALID }
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
          description: RecordingStudioAccessible::Api::OpenapiCopy::ACTOR_ID_REVOKE
        },
        actor_type: {
          type: :string,
          allow_blank: false,
          description: RecordingStudioAccessible::Api::OpenapiCopy::ACTOR_TYPE
        }
      },
      openapi: {
        title: RecordingStudioAccessible::Api::OpenapiCopy::REVOKE_ACCESS_TITLE,
        summary: RecordingStudioAccessible::Api::OpenapiCopy::REVOKE_ACCESS_SUMMARY,
        description: RecordingStudioAccessible::Api::REVOKE_ACCESS_DESCRIPTION,
        responses: {
          "200" => {
            description: RecordingStudioAccessible::Api::OpenapiCopy::REVOKE_OK,
            content: {
              "application/json" => {
                schema: RecordingStudioAccessible::Api::OpenapiSchemas::REVOKE_ACCESS
              }
            }
          },
          "403" => { description: RecordingStudioAccessible::Api::OpenapiCopy::FORBIDDEN },
          "404" => { description: RecordingStudioAccessible::Api::OpenapiCopy::MISSING },
          "422" => { description: RecordingStudioAccessible::Api::OpenapiCopy::REVOKE_INVALID }
        }
      }
    }
  }.freeze
)
