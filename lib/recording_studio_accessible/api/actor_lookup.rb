# frozen_string_literal: true

module RecordingStudioAccessible
  module Api
    module ActorLookup
      private

      def find_actor!(purpose: :lookup)
        actor_id = required_actor_id!
        type_name = requested_actor_type_name
        reject_disallowed_actor_type!(type_name)
        reject_ungrantable_actor_type!(type_name) if purpose == :grant

        resolve_actor(actor_id, type_name) || raise(not_found_error(Copy.t("errors.unknown_actor")))
      end

      def required_actor_id!
        actor_id = param(:actor_id)
        return actor_id if actor_id.present?

        raise invalid_input_error(Copy.t("errors.actor_required"), details: [Copy.t("errors.actor_required")])
      end

      def requested_actor_type_name
        given = param(:actor_type).to_s.strip.presence
        return given if given.present?
        return default_actor_type_name if default_actor_type_name

        raise invalid_input_error(Copy.t("errors.actor_type_required"), details: [Copy.t("errors.actor_type_required")])
      end

      def default_actor_type_name
        "User" if allowed_actor_type_name?("User")
      end

      def reject_disallowed_actor_type!(type_name)
        return if allowed_actor_type_name?(type_name)

        raise_actor_type_not_allowed!
      end

      def reject_ungrantable_actor_type!(type_name)
        return if grantable_actor_type_name?(type_name)

        raise_actor_type_not_allowed!
      end

      def raise_actor_type_not_allowed!
        raise invalid_input_error(
          Copy.t("errors.actor_type_not_allowed"),
          details: [Copy.t("errors.actor_type_not_allowed")]
        )
      end

      def allowed_actor_type_name?(type_name)
        return false if type_name.blank?
        return false unless type_name.match?(ACTOR_TYPE_NAME)

        configuration = RecordingStudioAccessible.configuration
        return true if configuration.all_access_actor_types_allowed?

        Array(configuration.access_actor_types).include?(type_name)
      end

      def grantable_actor_type_name?(type_name)
        RecordingStudioAccessible.configuration.grantable_actor_types_for(controller: nil).include?(type_name)
      end

      def resolve_actor(actor_id, type_name)
        klass = type_name.safe_constantize
        return unless klass.respond_to?(:find_by)

        actor = klass.find_by(id: actor_id)
        return unless actor
        return unless RecordingStudioAccessible.configuration.allowed_access_actor_type?(actor)

        actor
      end
    end
  end
end
