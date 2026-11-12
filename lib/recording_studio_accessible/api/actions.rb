# frozen_string_literal: true

module RecordingStudioAccessible
  module Api
    class ListAccess < Handler
      def call
        authorize_management!

        { grants: grant_list.rows.map { |row| Payload.grant_row(row) } + invitation_rows }
      end

      private

      def invitation_rows
        Payload.pending_invitation_rows(recording)
      end
    end

    class GrantAccess < Handler
      def call
        authorize_management!
        reject_mixed_actor_and_email!

        return invite_by_email(param(:email)) if param(:email).present?

        grant_to_actor
      end

      private

      def reject_mixed_actor_and_email!
        return unless param(:email).present? && param(:actor_id).present?

        raise invalid_input_error(
          Copy.t("errors.actor_or_email"),
          details: [Copy.t("errors.actor_or_email")]
        )
      end

      def invite_by_email(email)
        result = RecordingStudioAccessible.invite_access(
          recording: recording,
          email: email,
          role: param(:role),
          manager_actor: manager_actor
        )
        raise_service_failure!(result) if result.failure?

        serialize_invite_outcome(result.value)
      end

      def grant_to_actor
        actor = find_actor!(purpose: :grant)
        result = RecordingStudioAccessible.grant_access(
          recording: recording,
          actor: actor,
          role: param(:role),
          manager_actor: manager_actor
        )
        raise_service_failure!(result) if result.failure?

        notify_granted(actor)
        serialize_direct_grant(result.value)
      end

      def notify_granted(actor)
        RecordingStudioAccessible.configuration.notify_access_granted(
          controller: nil,
          recording: recording,
          actor: actor,
          role: param(:role),
          manager_actor: manager_actor
        )
      end

      def serialize_invite_outcome(outcome)
        if outcome.respond_to?(:invited?) && outcome.invited?
          return {
            invited: true,
            email: param(:email).to_s.strip.downcase,
            role: param(:role).to_s,
            notice: outcome.notice
          }
        end

        serialize_direct_grant(outcome.access_recording)
      end

      def serialize_direct_grant(access_recording)
        actor = access_recording.recordable.actor
        {
          invited: false,
          inherited: false,
          role: access_recording.recordable.role.to_s,
          effective_role: RecordingStudioAccessible.role_for(actor: actor, recording: recording)&.to_s,
          actor: Payload.actor(actor),
          source_recording: Payload.recording(recording),
          notice: Copy.t("flashes.access_granted")
        }
      end
    end

    class UpdateAccess < Handler
      def call
        authorize_management!
        result = RecordingStudioAccessible.update_access(
          recording: recording,
          access_recording: direct_access_recording_for!(find_actor!),
          role: param(:role),
          manager_actor: manager_actor
        )
        raise_service_failure!(result) if result.failure?

        serialize_updated(result.value)
      end

      private

      def serialize_updated(access_recording)
        actor = access_recording.recordable.actor
        {
          invited: false,
          inherited: false,
          role: access_recording.recordable.role.to_s,
          effective_role: RecordingStudioAccessible.role_for(actor: actor, recording: recording)&.to_s,
          actor: Payload.actor(actor),
          source_recording: Payload.recording(recording)
        }
      end
    end

    class RevokeAccess < Handler
      def call
        authorize_management!
        actor = find_actor!
        result = RecordingStudioAccessible.revoke_access(
          recording: recording,
          access_recording: direct_access_recording_for!(actor),
          manager_actor: manager_actor
        )
        raise_service_failure!(result) if result.failure?

        { revoked: true, actor: Payload.actor(actor) }
      end
    end

    class RevokeAccessInvitation < Handler
      def call
        authorize_management!
        invitation = invitation_on_recording
        result = RecordingStudioAccessible.revoke_access_invitation(
          invitation: invitation,
          manager_actor: manager_actor
        )
        raise_service_failure!(result) if result.failure?

        serialize_revoked_invitation(invitation, result.value)
      end
    end

    class ApproveAccessRequest < Handler
      def ensure_access_children!
        return if Compatibility.access_request_parent_allowed?(recording)

        raise not_found_error(Copy.t("errors.direct_access_not_enabled"))
      end

      def call
        authorize_management!
        result = RecordingStudioAccessible.approve_access_request(
          request_recording: request_recording_on_parent,
          manager_actor: manager_actor,
          role: param(:role)
        )
        raise_service_failure!(result) if result.failure?

        serialize_access_request(result.value)
      end
    end

    class DenyAccessRequest < Handler
      def ensure_access_children!
        return if Compatibility.access_request_parent_allowed?(recording)

        raise not_found_error(Copy.t("errors.direct_access_not_enabled"))
      end

      def call
        authorize_management!
        result = RecordingStudioAccessible.deny_access_request(
          request_recording: request_recording_on_parent,
          manager_actor: manager_actor,
          review_note: param(:review_note)
        )
        raise_service_failure!(result) if result.failure?

        serialize_access_request(result.value)
      end
    end
  end
end
