# frozen_string_literal: true

module RecordingStudioAccessible
  class AccessGrantedMailer < (defined?(::ApplicationMailer) ? ::ApplicationMailer : ActionMailer::Base)
    helper RecordingStudioAccessible::CopyHelper if respond_to?(:helper)

    def accessible_t(...)
      Copy.t(...)
    end

    class << self
      def display_label_for(actor)
        return Copy.t("mailers.someone") unless actor.present?

        %i[full_name name display_name].each do |method_name|
          next unless actor.respond_to?(method_name)

          value = actor.public_send(method_name)
          return value if value.present?
        end

        email = actor.email if actor.respond_to?(:email)
        return humanized_email_label(email) if email.present?

        Copy.t("mailers.someone")
      end

      def recordable_label_for(recording)
        recordable = recording&.recordable
        return nil unless recordable

        recordable_label_from_registry(recordable) ||
          recordable_label_from_methods(recordable) ||
          recordable.class.name.demodulize.presence
      end

      private

      def recordable_label_from_registry(recordable)
        return unless defined?(::RecordingStudio::Labels) && ::RecordingStudio::Labels.respond_to?(:title_for)

        ::RecordingStudio::Labels.title_for(recordable).presence
      end

      def recordable_label_from_methods(recordable)
        %i[recordable_name name title].each do |method_name|
          value = recordable.public_send(method_name) if recordable.respond_to?(method_name)
          return value if value.present?
        end

        nil
      end

      def humanized_email_label(email)
        local_part = email.to_s.split("@", 2).first.to_s.tr("._-", " ").squish.titleize
        local_part.presence || email
      end
    end

    def access_granted
      I18n.with_locale(mailer_locale) do
        @recording = params[:recording]
        @recording_label = self.class.recordable_label_for(@recording)
        @actor = params[:actor]
        @role = params[:role].to_s
        @role_label = Copy.role_name(@role).downcase
        @manager_actor = params[:manager_actor]
        @manager_actor_display_name = self.class.display_label_for(@manager_actor)
        @access_url = params[:access_url]
        @greeting_email = @actor.respond_to?(:email) ? @actor.email.to_s : ""

        mail(
          from: resolved_from_address,
          to: @actor.email,
          subject: params[:subject].presence || Copy.t("mailers.granted.subject")
        )
      end
    end

    private

    def mailer_locale
      params[:locale].presence || I18n.locale
    end

    def resolved_from_address
      self.class.default_params[:from].presence || ActionMailer::Base.default_params[:from].presence || "no-reply@example.com"
    end
  end
end
