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

      def normalize_name(name)
        value = name.to_s.strip
        return required_name if value.blank?
        raise AccessRequestIntake::Error, Copy.t("requests.errors.name_too_long") if name_too_long?(value)

        value
      end

      def name_required?
        return false unless defined?(::RecordingStudioUser)

        user_class = RecordingStudioUser.config.user_class
        attribute_required?(user_class, :name) || attribute_required?(user_class, :first_name)
      end

      def profile_attributes(submitted_name)
        first_name, last_name = submitted_name.to_s.strip.split(/\s+/, 2)
        return {} if first_name.blank?

        { first_name: first_name, last_name: last_name }
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

      def required_name
        raise AccessRequestIntake::Error, Copy.t("requests.errors.enter_name") if name_required?

        nil
      end

      def name_too_long?(value)
        value.length > AccessRequestIntent::NAME_MAX
      end

      def attribute_required?(model, attribute)
        return false unless model.respond_to?(:validators_on)

        model.validators_on(attribute).any? { |validator| validator.kind == :presence }
      end
    end
  end
end
