# frozen_string_literal: true

module RecordingStudioAccessible
  class Configuration
    module Invitations
      INVITATION_URL_KEYS = %i[controller raw_token email role recording manager_actor].freeze
      INVITATION_DELIVERY_KEYS = %i[controller recording email role manager_actor raw_token].freeze

      def access_invitation_actor_matches?(actor:, email:)
        resolve_configurable(access_invitation_actor_matcher, actor: actor, email: email) ? true : false
      rescue StandardError
        false
      end

      def access_invitation_url_for(**kwargs)
        resolve_invitation_url(fetch_keywords(kwargs, INVITATION_URL_KEYS))
      end

      def access_invitation_subject_for(controller:, recording:, email:, role:, manager_actor:)
        resolve_configurable(
          access_invitation_subject,
          controller: controller,
          recording: recording,
          email: email,
          role: role,
          manager_actor: manager_actor
        )
      rescue StandardError
        Copy.t("mailers.invitation.subject")
      end

      def access_notification_locale_for(**)
        locale_from_access_notification(**)
      rescue StandardError
        I18n.locale
      end

      def deliver_access_invitation(**kwargs)
        deliver_fetched_invitation(fetch_keywords(kwargs, INVITATION_DELIVERY_KEYS))
      end

      def access_invitation_sign_in_url_for(controller:, token:, email:)
        return if access_invitation_sign_in_url_resolver.nil?

        resolve_configurable(
          access_invitation_sign_in_url_resolver,
          controller: controller,
          token: token,
          email: email
        )
      rescue StandardError
        nil
      end

      private

      def deliver_fetched_invitation(arguments)
        invitation_delivery_succeeded?(
          resolve_configurable(access_invitation_notifier, **arguments)
        )
      rescue StandardError
        false
      end

      def assign_invitation_defaults
        @access_invitation_ttl = 14.days
        @access_invitation_actor_matcher = default_invitation_actor_matcher
        @access_invitation_notifier = method(:default_access_invitation_notifier)
        @access_invitation_subject = method(:default_access_invitation_subject)
        @access_invitation_url_resolver = method(:default_access_invitation_url_resolver)
        @access_invitation_sign_in_url_resolver = nil
        @access_notification_locale = nil
      end

      def default_invitation_actor_matcher
        lambda do |actor:, email:|
          actor.respond_to?(:email) && actor.email.to_s.strip.downcase == email
        end
      end

      def resolve_invitation_url(arguments)
        resolve_configurable(access_invitation_url_resolver, **arguments)
      rescue StandardError
        nil
      end

      def locale_from_access_notification(**)
        callable = access_notification_locale
        if callable.respond_to?(:call)
          resolve_configurable(callable, **).presence || I18n.locale
        elsif callable.present?
          callable
        else
          I18n.locale
        end
      end

      def default_access_invitation_subject(**kwargs)
        recording_label = recording_notification_label(kwargs[:recording])
        return Copy.t("mailers.invitation.subject") if recording_label.blank?

        Copy.t("mailers.invitation.subject_with_recording", recording: recording_label)
      rescue StandardError
        Copy.t("mailers.invitation.subject")
      end
    end
  end
end
