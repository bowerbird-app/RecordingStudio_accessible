# frozen_string_literal: true

require "securerandom"

module RecordingStudioAccessible
  # Keeps a disabled address on the same code page, and drops a user row when
  # the send is refused. Recording Studio Users still rate-limits only after a
  # user exists; this guard cleans up that window for access requests.
  module AccessRequestOtpGuard
    class << self
      def issue(account, request, session, &)
        return held(account, request, session) if account.hold

        created(account, &)
      end

      def issue_otp!(user:, purpose:, request:, session:)
        call_users do
          RecordingStudioUser.issue_otp!(
            user: user, purpose: purpose, request: request, session: session, rate_limit_scope: :issue
          )
        end
      end

      def call_users(&block)
        block.call
      rescue RecordingStudioUser::RateLimited
        raise AccessRequestIntake::Error, Copy.t("requests.errors.rate_limited")
      end

      def quiet_resend(intent, request, session)
        consume(:resend, intent.email, request, session)
        ticket(intent.otp_challenge_id)
      end

      private

      def created(account, &block)
        block.call
      rescue StandardError
        discard!(account)
        raise
      end

      def held(account, request, session)
        consume(:issue, account.user.email, request, session)
        ticket(SecureRandom.uuid)
      end

      def discard!(account)
        return unless account.created && !account.user.confirmed?

        account.user.destroy!
      rescue StandardError
        nil
      end

      def consume(scope, email, request, session)
        keys(email, request, session).each do |key|
          RecordingStudioUser::Services::OtpRateLimiter.allow_request!(scope: scope, key: key)
        end
      rescue RecordingStudioUser::RateLimited
        raise AccessRequestIntake::Error, Copy.t("requests.errors.rate_limited")
      end

      def keys(email, request, session)
        [email, request&.remote_ip, session_key(session)].compact
      end

      def session_key(session)
        return unless session.respond_to?(:id) && !session.is_a?(Hash)

        session.id
      end

      def ticket(challenge_id)
        Struct.new(:challenge_id).new(challenge_id)
      end
    end
  end
end
