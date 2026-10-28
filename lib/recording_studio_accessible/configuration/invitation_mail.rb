# frozen_string_literal: true

module RecordingStudioAccessible
  class Configuration
    module InvitationMail
      private

      def default_access_invitation_notifier(**kwargs)
        return false unless defined?(RecordingStudioAccessible::AccessInvitationMailer)

        acceptance_url = access_invitation_url_for(**invitation_url_arguments(kwargs))
        return false if acceptance_url.blank?

        deliver_invitation_mail(kwargs.merge(acceptance_url: acceptance_url))
      rescue StandardError
        false
      end

      def invitation_url_arguments(kwargs)
        {
          controller: kwargs[:controller],
          raw_token: kwargs[:raw_token],
          email: kwargs[:email],
          role: kwargs[:role],
          recording: kwargs[:recording],
          manager_actor: kwargs[:manager_actor]
        }
      end

      def deliver_invitation_mail(kwargs)
        locale = invitation_mail_locale(kwargs)
        I18n.with_locale(locale) do
          deliver_notification(invitation_mail_for(kwargs, locale), locale: locale).present?
        end
      end

      def invitation_mail_locale(kwargs)
        access_notification_locale_for(
          controller: kwargs[:controller],
          recording: kwargs[:recording],
          email: kwargs[:email],
          role: kwargs[:role],
          manager_actor: kwargs[:manager_actor]
        )
      end

      def invitation_mail_for(kwargs, locale)
        RecordingStudioAccessible::AccessInvitationMailer.with(
          email: kwargs[:email],
          recording: kwargs[:recording],
          role: kwargs[:role],
          manager_actor: kwargs[:manager_actor],
          acceptance_url: kwargs[:acceptance_url],
          locale: locale,
          subject: invitation_mail_subject(kwargs)
        ).access_invitation
      end

      def invitation_mail_subject(kwargs)
        access_invitation_subject_for(
          controller: kwargs[:controller],
          recording: kwargs[:recording],
          email: kwargs[:email],
          role: kwargs[:role],
          manager_actor: kwargs[:manager_actor]
        )
      end

      def default_access_invitation_url_resolver(**kwargs)
        options = access_invitation_url_options(kwargs[:controller])
        return if options.blank?

        RecordingStudioAccessible::Engine.routes.url_helpers.access_invitation_url(
          token: kwargs[:raw_token],
          **options
        )
      rescue StandardError
        nil
      end

      def recording_notification_label(recording)
        return if recording.blank?
        return unless defined?(::RecordingStudio::Labels) && recording.respond_to?(:recordable)

        ::RecordingStudio::Labels.title_for(recording.recordable).presence
      end

      def access_invitation_url_options(controller)
        request = controller.request if controller.respond_to?(:request)
        return mailer_url_options unless request

        invitation_request_url_options(request)
      rescue StandardError
        mailer_url_options
      end

      def invitation_request_url_options(request)
        options = { host: request.host, protocol: request.protocol }
        options[:port] = request.port if request.respond_to?(:port) && request.port.present?
        script_name = request.script_name if request.respond_to?(:script_name)
        options[:script_name] = script_name if script_name.present?
        options
      end

      def mailer_url_options
        ActionMailer::Base.default_url_options.to_h.symbolize_keys
      rescue StandardError
        {}
      end
    end
  end
end
