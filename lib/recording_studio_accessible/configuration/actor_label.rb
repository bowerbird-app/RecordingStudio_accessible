# frozen_string_literal: true

module RecordingStudioAccessible
  class Configuration
    module ActorLabel
      private

      def default_access_management_actor_label(actor)
        return Copy.t("errors.unknown_actor") unless actor

        actor_display_name(actor) || "#{actor.class.name.demodulize} ##{actor.id}"
      end

      def actor_display_name(actor)
        present_actor_string(read_actor_attribute(actor, :first_name)) ||
          present_actor_string(recording_studio_user_first_name(actor)) ||
          present_actor_string(read_actor_attribute(actor, :name)) ||
          present_actor_string(read_actor_attribute(actor, :email))
      end

      def recording_studio_user_first_name(actor)
        return unless defined?(::RecordingStudioUser)
        return unless RecordingStudioUser.respond_to?(:profile_for)

        profile = RecordingStudioUser.profile_for(actor)
        return unless profile.respond_to?(:first_name)

        profile.first_name
      rescue StandardError
        nil
      end

      def read_actor_attribute(actor, method_name)
        return unless actor.respond_to?(method_name)

        actor.public_send(method_name)
      rescue StandardError
        nil
      end

      def present_actor_string(value)
        value.to_s.squish.presence
      end
    end
  end
end
