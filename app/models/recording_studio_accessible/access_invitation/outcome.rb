# frozen_string_literal: true

module RecordingStudioAccessible
  class AccessInvitation
    class Outcome
      attr_reader :access_recording, :notice, :pending

      def self.granted(access_recording: nil, notice: "Access granted.")
        new(kind: :granted, access_recording: access_recording, notice: notice)
      end

      def self.invited(pending:, notice: "Invitation sent.")
        new(kind: :invited, pending: pending, notice: notice)
      end

      def self.revoked(notice: "Invitation revoked.")
        new(kind: :revoked, notice: notice)
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
