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
        present_actor_string(joined_person_name(actor)) ||
          present_actor_string(joined_person_name(recording_studio_user_profile(actor))) ||
          present_actor_string(read_actor_attribute(actor, :name)) ||
          present_actor_string(read_actor_attribute(actor, :email))
      end

      def joined_person_name(person)
        return unless person

        [
          present_actor_string(read_actor_attribute(person, :first_name)),
          present_actor_string(read_actor_attribute(person, :last_name))
        ].compact.join(" ").presence
      end

      def recording_studio_user_profile(actor)
        return unless defined?(::RecordingStudioUser)
        return unless RecordingStudioUser.respond_to?(:profile_for)

        RecordingStudioUser.profile_for(actor)
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
