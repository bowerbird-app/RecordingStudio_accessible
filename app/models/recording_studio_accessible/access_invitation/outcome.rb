# frozen_string_literal: true

module RecordingStudioAccessible
  class AccessInvitation
    class Outcome
      attr_reader :access_recording, :notice, :pending

      def self.granted(access_recording: nil, notice: nil)
        new(kind: :granted, access_recording: access_recording,
            notice: notice || Copy.t("flashes.access_granted"))
      end

      def self.invited(pending:, notice: nil)
        new(kind: :invited, pending: pending, notice: notice || Copy.t("flashes.invitation_sent"))
      end

      def self.revoked(notice: nil)
        new(kind: :revoked, notice: notice || Copy.t("flashes.invitation_revoked"))
      end

      def initialize(kind:, access_recording: nil, notice: nil, pending: nil)
        @kind = kind
        @access_recording = access_recording
        @notice = notice
        @pending = pending
      end

      def granted?
        @kind == :granted
      end

      def invited?
        @kind == :invited
      end

      def revoked?
        @kind == :revoked
      end
    end
  end
end
