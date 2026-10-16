# frozen_string_literal: true

require "securerandom"

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
        result = request_code(normalized, request, session)
        create_intent(recording, normalized, submitted, role, action, result)
      end

      def request_code(email, request, session)
        purpose = AccessRequestAccount.purpose_for(email)
        raise Error, Copy.t("requests.errors.users_required") unless
          AccessRequestAccount.purpose_enabled?(purpose)

        accept_code(
          RecordingStudioUser.request_otp!(email: email, purpose: purpose, request: request, session: session)
        )
      end

      def accept_code(result)
        raise Error, Copy.t("requests.errors.rate_limited") if result.throttled?

        result
      end

      def create_intent(recording, email, submitted_name, role, action, result)
        AccessRequestIntent.create!(intent_row(recording, email, submitted_name, role, action, result))
      end

      def intent_row(recording, email, submitted_name, role, action, result)
        {
          recording_id: recording.id, user_id: intent_user_id(email, result),
          otp_challenge_id: result.challenge_id || SecureRandom.uuid, email: email,
          submitted_name: submitted_name, role: role.to_s.strip.presence,
          action: action.to_s.strip.presence, expires_at: AccessRequestIntent::LIFETIME.from_now
        }
      end

      def intent_user_id(email, result)
        result.challenge&.user_id || AccessRequestAccount.user_id_for(email) ||
          raise(Error, Copy.t("requests.errors.email_unavailable"))
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
        result = accept_code(send_again(intent, request, session))
        intent.update!(otp_challenge_id: result.challenge_id || intent.otp_challenge_id)
        intent
      end

      def send_again(intent, request, session)
        proof = RecordingStudioUser.otp_proof(intent.otp_challenge_id)
        return request_again(intent, request, session) if proof.nil?

        user = RecordingStudioUser.config.user_class.find(intent.user_id)
        RecordingStudioUser.resend_otp!(user: user, purpose: proof.purpose, request: request, session: session)
      end

      def request_again(intent, request, session)
        RecordingStudioUser.request_otp!(
          email: intent.email, purpose: AccessRequestAccount.purpose_for(intent.email),
          request: request, session: session
        )
      end

      def verify_code(intent, code, session)
        proof = RecordingStudioUser.otp_proof(intent.otp_challenge_id)
        raise Error, Copy.t("requests.errors.code_mismatch") if proof.nil?

        RecordingStudioUser.verify_otp!(
          challenge_id: intent.otp_challenge_id, code: code, purpose: proof.purpose, session: session
        )
      end
    end
  end
end
