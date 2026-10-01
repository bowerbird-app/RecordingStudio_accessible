# frozen_string_literal: true

module RecordingStudioAccessible
  class AccessInvitation
    class PendingInvitation
      attr_reader :id, :email, :role, :expires_at, :last_sent_at, :expired

      def self.from(invitation)
        new(
          id: invitation.id,
          email: invitation.email,
          role: invitation.role,
          expires_at: invitation.expires_at,
          last_sent_at: invitation.last_sent_at,
          expired: invitation.expired?
        )
      end

      def initialize(attrs)
        @id = attrs[:id]
        @email = attrs[:email]
        @role = attrs[:role]
        @expires_at = attrs[:expires_at]
        @last_sent_at = attrs[:last_sent_at]
        @expired = attrs[:expired]
      end
    end
  end
end
