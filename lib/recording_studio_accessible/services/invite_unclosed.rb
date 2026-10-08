# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    module InviteUnclosed
      private

      def invite_unknown(manager)
        existing = unclosed_invitation
        return resend_unclosed(existing, manager) if existing

        create_and_deliver(manager)
      end

      def create_and_deliver(manager)
        raw_token = fresh_invitation_token
        invitation = AccessInvitation.insert_unclosed!(
          recording: @recording,
          email: @email,
          role: @role,
          manager_actor: manager,
          raw_token: raw_token
        )
        return failure(copy("errors.invitation_not_sent")) unless deliver_invitation(manager, raw_token)
        return failure(copy("errors.invitation_not_saved")) unless delivered_token_current?(raw_token)

        invited_result(invitation)
      rescue ActiveRecord::RecordNotUnique
        existing = unclosed_invitation
        return failure(copy("errors.invitation_not_saved")) unless existing

        resend_unclosed(existing, manager)
      end

      def resend_unclosed(invitation, manager)
        raw_token = fresh_invitation_token
        expected_digest = invitation.token_digest
        return failure(copy("errors.invitation_not_sent")) unless deliver_invitation(manager, raw_token)

        committed = AccessInvitation.commit_resend!(
          invitation: invitation,
          expected_digest: expected_digest,
          role: @role,
          manager_actor: manager,
          raw_token: raw_token
        )
        return failure(copy("errors.invitation_not_saved")) unless committed

        invited_result(invitation)
      end

      def unclosed_invitation
        AccessInvitation.unclosed.find_by(recording_id: @recording.id, email: @email)
      end

      def delivered_token_current?(raw_token)
        AccessInvitation.locate(raw_token)&.id == unclosed_invitation&.id
      end

      def invited_result(invitation)
        pending = AccessInvitation::PendingInvitation.from(invitation.reload)
        success(AccessInvitation::Outcome.invited(pending: pending))
      end
    end
  end
end
