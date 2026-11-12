# frozen_string_literal: true

module RecordingStudioAccessible
  module Api
    ACTION_DEFINITIONS = {
      list_access: {
        handler: ListAccess, fields: {},
        openapi: {
          summary: "List access",
          description: "Lists direct and inherited grants, plus pending email invitations, on this recording.",
          responses: { "200" => { description: "Grants and pending invitations on this recording." } }
                     .merge(MANAGE_ACCESS_ERRORS)
        }
      },
      grant_access: {
        handler: GrantAccess,
        fields: {
          actor_id: { type: :string, allow_blank: false },
          actor_type: { type: :string, allow_blank: false },
          email: { type: :string, allow_blank: false },
          role: REQUIRED_ROLE_FIELD
        },
        openapi: {
          summary: "Grant access",
          description: "Grants a role to an actor id plus actor_type, or invites an email.",
          responses: { "200" => { description: "Access granted or invitation stored." },
                       "422" => { description: "Grant request is invalid." } }.merge(MANAGE_ACCESS_ERRORS)
        }
      },
      update_access: {
        handler: UpdateAccess,
        fields: {
          actor_id: { type: :string, required: true, allow_blank: false },
          actor_type: { type: :string, allow_blank: false },
          role: REQUIRED_ROLE_FIELD
        },
        openapi: {
          summary: "Update access",
          description: "Changes the role of a direct grant on this recording.",
          responses: { "200" => { description: "Direct grant updated." },
                       "422" => { description: "Update request is invalid." } }.merge(MANAGE_ACCESS_ERRORS)
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
          responses: { "200" => { description: "Direct grant removed." },
                       "422" => { description: "Revoke request is invalid." } }.merge(MANAGE_ACCESS_ERRORS)
        }
      },
      revoke_access_invitation: {
        handler: RevokeAccessInvitation,
        fields: { invitation_id: { type: :string, required: true, allow_blank: false } },
        openapi: {
          title: "Access Invitation - Revoke", summary: "Access Invitation - Revoke",
          description: "Withdraws a pending invitation on this recording. Leaves any access grant alone.",
          responses: { "200" => { description: "Invitation withdrawn." },
                       "422" => { description: "Invitation is missing or cannot be revoked." } }
                     .merge(MANAGE_ACCESS_ERRORS)
        }
      },
      approve_access_request: {
        handler: ApproveAccessRequest,
        fields: {
          request_recording_id: { type: :string, required: true, allow_blank: false },
          role: ROLE_FIELD
        },
        openapi: {
          title: "Access Request - Approve", summary: "Access Request - Approve",
          description: "Approves a pending access request on this recording and grants the role.",
          responses: { "200" => { description: "Access request approved." },
                       "422" => { description: "Approve request is invalid." } }.merge(MANAGE_ACCESS_ERRORS)
        }
      },
      deny_access_request: {
        handler: DenyAccessRequest,
        fields: {
          request_recording_id: { type: :string, required: true, allow_blank: false },
          review_note: { type: :string, allow_blank: false }
        },
        openapi: {
          title: "Access Request - Deny", summary: "Access Request - Deny",
          description: "Denies a pending access request on this recording.",
          responses: { "200" => { description: "Access request denied." },
                       "422" => { description: "Deny request is invalid." } }.merge(MANAGE_ACCESS_ERRORS)
        }
      }
    }.freeze
  end
end
