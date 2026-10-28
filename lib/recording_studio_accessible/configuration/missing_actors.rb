# frozen_string_literal: true

module RecordingStudioAccessible
  class Configuration
    module MissingActors
      def resolve_missing_actor(controller:, email:, recording:, role:, manager_actor:)
        result = resolve_configurable(
          access_management_missing_actor_handler,
          controller: controller,
          email: email,
          recording: recording,
          role: role,
          manager_actor: manager_actor
        )

        normalize_missing_actor_resolution(result, email: email)
      end

      def missing_actor_error_for_email(email:)
        default_missing_actor_error_for_email(email: email)
      end

      private

      def assign_missing_actor_defaults
        @access_management_missing_actor_handler = method(:default_access_management_missing_actor_handler)
      end

      def default_access_management_missing_actor_handler(**kwargs)
        email = kwargs[:email]
        _controller = kwargs[:controller]
        _recording = kwargs[:recording]
        _role = kwargs[:role]
        _manager_actor = kwargs[:manager_actor]
        unresolved_or_invalid_missing_actor(email)
      rescue StandardError
        MissingActorResolution.invalid(error: default_missing_actor_error_for_email(email: kwargs[:email]))
      end

      def unresolved_or_invalid_missing_actor(email)
        normalized_email = email.to_s.strip.downcase
        if normalized_email.blank?
          return MissingActorResolution.invalid(error: default_missing_actor_error_for_email(email: email))
        end

        MissingActorResolution.unresolved
      end

      def default_missing_actor_error_for_email(email:)
        normalized_email = email.to_s.strip
        return Copy.t("errors.user_required") if normalized_email.blank?

        Copy.t("errors.user_not_found", email: normalized_email)
      end

      def default_missing_actor_notice_for_email(email:)
        "Access granted to #{email}"
      end

      def normalize_missing_actor_resolution(result, email:)
        return invalid_missing_actor(email) if result.nil?
        return result if result.is_a?(MissingActorResolution)
        return normalize_missing_actor_resolution_hash(result, email: email) if result.is_a?(Hash)

        MissingActorResolution.found(actor: result)
      end

      def normalize_missing_actor_resolution_hash(result, email:)
        attributes = result.transform_keys(&:to_sym)
        status = (attributes[:status] || :invalid).to_sym
        redirected = redirect_missing_actor_resolution(status, attributes)
        return redirected if redirected
        return MissingActorResolution.new(**attributes) if usable_missing_actor_hash?(status, attributes)

        invalid_missing_actor(email)
      end

      def redirect_missing_actor_resolution(status, attributes)
        return unless %i[redirect requires_resolution].include?(status) && attributes[:location].present?

        MissingActorResolution.redirect(
          location: attributes[:location],
          notice: attributes[:notice],
          alert: attributes[:alert],
          status: status
        )
      end

      def usable_missing_actor_hash?(status, attributes)
        attributes[:actor].present? || attributes[:error].present? || %i[invited unresolved].include?(status)
      end

      def invalid_missing_actor(email)
        MissingActorResolution.invalid(error: default_missing_actor_error_for_email(email: email))
      end
    end
  end
end
