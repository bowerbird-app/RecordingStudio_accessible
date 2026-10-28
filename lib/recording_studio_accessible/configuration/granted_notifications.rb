# frozen_string_literal: true

module RecordingStudioAccessible
  class Configuration
    module GrantedNotifications
      def notify_access_granted(controller:, recording:, actor:, role:, manager_actor:)
        resolve_configurable(
          access_management_access_granted_notifier,
          controller: controller,
          recording: recording,
          actor: actor,
          role: role,
          manager_actor: manager_actor
        )
      end

      def access_granted_subject_for(controller:, recording:, actor:, role:, manager_actor:)
        resolve_access_granted_subject(
          controller: controller,
          recording: recording,
          actor: actor,
          role: role,
          manager_actor: manager_actor
        )
      end

      def access_granted_url_for(controller:, recording:, actor:, role:, manager_actor:)
        resolve_access_granted_url(
          controller: controller,
          recording: recording,
          actor: actor,
          role: role,
          manager_actor: manager_actor
        )
      end

      private

      def assign_granted_notification_defaults
        @access_management_access_granted_notifier = method(:default_access_management_access_granted_notifier)
        @access_management_access_granted_subject = method(:default_access_management_access_granted_subject)
        @access_management_access_granted_url_resolver = method(:default_access_management_access_granted_url_resolver)
      end

      def default_access_management_access_granted_notifier(**kwargs)
        actor = kwargs[:actor]
        return unless actor.respond_to?(:email)

        recipient_email = actor.email.to_s.strip
        return if recipient_email.blank?
        return unless defined?(RecordingStudioAccessible::AccessGrantedMailer)

        deliver_granted_notification(kwargs.merge(recipient_email: recipient_email))
      rescue StandardError
        nil
      end

      def deliver_granted_notification(kwargs)
        locale = granted_notification_locale(kwargs)
        I18n.with_locale(locale) do
          deliver_notification(granted_mail_for(kwargs, locale), locale: locale)
        end
      end

      def granted_notification_locale(kwargs)
        access_notification_locale_for(
          controller: kwargs[:controller],
          recording: kwargs[:recording],
          actor: kwargs[:actor],
          email: kwargs[:recipient_email],
          role: kwargs[:role],
          manager_actor: kwargs[:manager_actor]
        )
      end

      def granted_mail_for(kwargs, locale)
        RecordingStudioAccessible::AccessGrantedMailer.with(
          controller: kwargs[:controller],
          recording: kwargs[:recording],
          actor: kwargs[:actor],
          role: kwargs[:role],
          manager_actor: kwargs[:manager_actor],
          locale: locale,
          subject: access_granted_subject_for(**granted_mail_arguments(kwargs)),
          access_url: access_granted_url_for(**granted_mail_arguments(kwargs))
        ).access_granted
      end

      def granted_mail_arguments(kwargs)
        {
          controller: kwargs[:controller],
          recording: kwargs[:recording],
          actor: kwargs[:actor],
          role: kwargs[:role],
          manager_actor: kwargs[:manager_actor]
        }
      end

      def default_access_management_access_granted_subject(**kwargs)
        recording_label = recording_notification_label(kwargs[:recording])
        return Copy.t("mailers.granted.subject") if recording_label.blank?

        Copy.t("mailers.granted.subject_with_recording", recording: recording_label)
      rescue StandardError
        Copy.t("mailers.granted.subject")
      end

      def resolve_access_granted_url(**)
        resolve_configurable(access_management_access_granted_url_resolver, **)
      end

      def resolve_access_granted_subject(**)
        resolve_configurable(access_management_access_granted_subject, **)
      end
    end
  end
end
