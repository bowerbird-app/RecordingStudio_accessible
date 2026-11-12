# frozen_string_literal: true

module RecordingStudioAccessible
  module Api
    REQUEST_ACTION_DEFINITIONS = {
      revoke_access_invitation: {
        handler: RevokeAccessInvitation,
        fields: { invitation_id: { type: :string, required: true, allow_blank: false } },
        openapi: {
          title: "Access Invitation - Revoke",
          summary: "Withdraws a pending invitation on this recording.",
          description: "Withdraws a pending invitation on this recording. Leaves any access grant alone.",
          responses: {
            "200" => { description: "Invitation withdrawn." },
            "403" => { description: "Not allowed to manage access." },
            "404" => { description: "Direct access is not enabled for this recording." },
            "422" => { description: "Invitation is missing or cannot be revoked." }
          }
        }
      },
      approve_access_request: {
        handler: ApproveAccessRequest,
        fields: {
          request_recording_id: { type: :string, required: true, allow_blank: false },
          role: {
            type: :string,
            allow_blank: false,
            description:
              "Default roles: #{RecordingStudioAccessible::RoleSet::DEFAULT_NAMES.join(', ')}. " \
              "Types may declare others."
          }
        },
        openapi: {
          title: "Access Request - Approve",
          summary: "Approves a pending request and grants the role.",
          description: "Approves a pending access request on this recording and grants the role.",
          responses: {
            "200" => { description: "Access request approved." },
            "403" => { description: "Not allowed to manage access." },
            "404" => { description: "Direct access is not enabled for this recording." },
            "422" => { description: "Approve request is invalid." }
          }
        }
      },
      deny_access_request: {
        handler: DenyAccessRequest,
        fields: {
          request_recording_id: { type: :string, required: true, allow_blank: false },
          review_note: { type: :string, allow_blank: false }
        },
        openapi: {
          title: "Access Request - Deny",
          summary: "Denies a pending access request on this recording.",
          description: "Denies a pending access request on this recording.",
          responses: {
            "200" => { description: "Access request denied." },
            "403" => { description: "Not allowed to manage access." },
            "404" => { description: "Direct access is not enabled for this recording." },
            "422" => { description: "Deny request is invalid." }
          }
        }
      }
    }.freeze
  end
end
