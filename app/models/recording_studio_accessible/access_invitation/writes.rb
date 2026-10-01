# frozen_string_literal: true

module RecordingStudioAccessible
  class AccessInvitation
    module Writes
      def insert_unclosed!(recording:, email:, role:, manager_actor:, raw_token:)
        recording.transaction(requires_new: true) do
          recording.lock!
          raise ActiveRecord::RecordNotUnique, "unclosed invitation exists" if unclosed_exists?(recording, email)

          create!(unclosed_attributes(role, manager_actor, raw_token).merge(recording: recording, email: email))
        end
      end

      def commit_resend!(invitation:, expected_digest:, role:, manager_actor:, raw_token:)
        invitation.transaction(requires_new: true) do
          invitation.lock!
          next unless resend_still_current?(invitation, expected_digest)

          invitation.update!(unclosed_attributes(role, manager_actor, raw_token))
          invitation
        end
      rescue ActiveRecord::RecordNotUnique
        nil
      end

      private

      def resend_still_current?(invitation, expected_digest)
        invitation.unclosed? && invitation.token_digest == expected_digest
      end

      def unclosed_exists?(recording, email)
        unclosed.exists?(recording_id: recording.id, email: email)
      end

      def unclosed_attributes(role, manager_actor, raw_token)
        now = Time.current
        {
          role: role.to_s,
          manager_actor: manager_actor,
          token_digest: Digest::SHA256.hexdigest(raw_token),
          expires_at: now + RecordingStudioAccessible.configuration.access_invitation_ttl,
          last_sent_at: now
        }
      end
    end
  end
end
