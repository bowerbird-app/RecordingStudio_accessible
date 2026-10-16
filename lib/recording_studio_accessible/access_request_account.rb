# frozen_string_literal: true

module RecordingStudioAccessible
  module AccessRequestAccount
    class << self
      def normalize_email(email)
        normalized = email.to_s.strip.downcase
        raise AccessRequestIntake::Error, Copy.t("requests.errors.enter_email") unless email_shaped?(normalized)

        normalized
      end

      def lookup(email)
        existing = RecordingStudioUser.config.user_class.find_by(email: email)
        return new_registration(email) if existing.nil?
        return registration(existing) unless existing.confirmed?
        return login(existing) if existing.active_for_authentication?

        unavailable
      end

      private

      def new_registration(email)
        require_otp!(:registration)
        [RecordingStudioUser.create_unconfirmed_user!(email: email), "registration"]
      rescue ActiveRecord::RecordNotUnique
        unavailable
      end

      def registration(user)
        require_otp!(:registration)
        [user, "registration"]
      end

      def login(user)
        require_otp!(:login)
        [user, "login"]
      end

      def require_otp!(kind)
        return if otp_enabled?(kind)

        raise AccessRequestIntake::Error, Copy.t("requests.errors.users_required")
      end

      def otp_enabled?(kind)
        config = RecordingStudioUser.config
        kind == :login ? config.otp_login_enabled? : config.otp_registration_enabled?
      end

      def email_shaped?(normalized)
        local, domain = normalized.split("@", 2)
        normalized.count("@") == 1 && local.present? && domain.present? && domain.include?(".")
      end

      def unavailable
        raise AccessRequestIntake::Error, Copy.t("requests.errors.email_unavailable")
      end
    end
  end
end
