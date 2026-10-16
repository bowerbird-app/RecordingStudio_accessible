# frozen_string_literal: true

module RecordingStudioAccessible
  module AccessRequestAccount
    class << self
      def normalize_email(email)
        normalized = email.to_s.strip.downcase
        raise AccessRequestIntake::Error, Copy.t("requests.errors.enter_email") unless email_shaped?(normalized)

        normalized
      end

      def purpose_for(email)
        return "login" if confirmed?(user_class.find_by(email: email))

        "registration"
      end

      def purpose_enabled?(purpose)
        config = RecordingStudioUser.config
        purpose == "login" ? config.otp_login_enabled? : config.otp_registration_enabled?
      end

      def user_id_for(email)
        user_class.find_by(email: email)&.id
      end

      def normalize_name(name)
        value = name.to_s.strip
        return required_name if value.blank?
        raise AccessRequestIntake::Error, Copy.t("requests.errors.name_too_long") if name_too_long?(value)

        value
      end

      def name_required?
        return false unless defined?(::RecordingStudioUser)

        user = user_class
        attribute_required?(user, :name) || attribute_required?(user, :first_name)
      end

      def profile_attributes(submitted_name)
        first_name, last_name = submitted_name.to_s.strip.split(/\s+/, 2)
        return {} if first_name.blank?

        { first_name: first_name, last_name: last_name }
      end

      private

      def confirmed?(user)
        return false if user.nil?

        user.respond_to?(:confirmed?) && user.confirmed?
      end

      def user_class
        RecordingStudioUser.config.user_class
      end

      def email_shaped?(normalized)
        local, domain = normalized.split("@", 2)
        normalized.count("@") == 1 && local.present? && domain.present? && domain.include?(".")
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
