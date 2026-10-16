# frozen_string_literal: true

module RecordingStudioAccessible
  module AccessRequestIntake
    class Error < RecordingStudioAccessible::Error; end

    SESSION_KEY = :recording_studio_accessible_access_request_intent_id

    class << self
      def start!(recording:, email:, role:, action:, request:, session:, name: nil)
        raise Error, Copy.t("requests.errors.users_required") unless users_ready?

        intent = open_intent(recording, email, role, action, request, session, name)
        session[SESSION_KEY] = intent.id
        intent
      end

      def name_required?
        AccessRequestAccount.name_required?
      end

      def verify!(intent:, code:, session:)
        raise Error, Copy.t("requests.errors.expired") if intent.expired?

        fulfill(intent, verified_user(intent, code, session))
      rescue ArgumentError
        raise Error, Copy.t("requests.errors.code_mismatch")
      end

      def resend!(intent:, request:, session:)
        raise Error, Copy.t("requests.errors.expired") if intent.expired? || intent.fulfilled?

        replace_challenge(intent, request, session)
      end

      private

      def users_ready?
        defined?(::RecordingStudioUser) && RecordingStudioUser.config.otp_enabled?
      end

      def open_intent(recording, email, role, action, request, session, name)
        normalized = AccessRequestAccount.normalize_email(email)
        submitted = AccessRequestAccount.normalize_name(name)
        user, purpose = AccessRequestAccount.lookup(normalized)
        issued = issue_otp!(user: user, purpose: purpose, request: request, session: session)
        create_intent(recording, user, issued, normalized, submitted, role, action)
      end

      def create_intent(recording, user, issued, email, submitted_name, role, action)
        AccessRequestIntent.create!(
          recording_id: recording.id,
          user_id: user.id,
          otp_challenge_id: issued.challenge_id,
          email: email,
          submitted_name: submitted_name,
          role: role.to_s.strip.presence,
          action: action.to_s.strip.presence,
          expires_at: AccessRequestIntent::LIFETIME.from_now
        )
      end

      def verified_user(intent, code, session)
        result = verify_code(intent, code, session)
        raise Error, Copy.t("requests.errors.code_mismatch") unless result.success?

        result.user
      end

      def fulfill(intent, user)
        RecordingStudioUser.complete_email_proof!(
          user: user,
          challenge_id: intent.otp_challenge_id,
          profile_attributes: AccessRequestAccount.profile_attributes(intent.submitted_name)
        )
        intent.update!(fulfilled_at: Time.current)
        user
      end

      def replace_challenge(intent, request, session)
        issued = reissue_otp(intent, request, session)
        intent.update!(otp_challenge_id: issued.challenge_id)
        intent
      end

      def reissue_otp(intent, request, session)
        user = RecordingStudioUser.config.user_class.find(intent.user_id)
        proof = RecordingStudioUser.otp_proof(intent.otp_challenge_id)
        raise Error, Copy.t("requests.errors.code_mismatch") if proof.nil?

        call_users_otp do
          RecordingStudioUser.resend_otp!(user: user, purpose: proof.purpose, request: request, session: session)
        end
      end

      def issue_otp!(user:, purpose:, request:, session:)
        call_users_otp do
          RecordingStudioUser.issue_otp!(
            user: user,
            purpose: purpose,
            request: request,
            session: session,
            rate_limit_scope: :issue
          )
        end
      end

      def verify_code(intent, code, session)
        proof = RecordingStudioUser.otp_proof(intent.otp_challenge_id)
        raise Error, Copy.t("requests.errors.code_mismatch") if proof.nil?

        RecordingStudioUser.verify_otp!(
          challenge_id: intent.otp_challenge_id,
          code: code,
          purpose: proof.purpose,
          session: session
        )
      end

      def call_users_otp
        yield
      rescue RecordingStudioUser::RateLimited
        raise Error, Copy.t("requests.errors.rate_limited")
      end
    end
  end
end
