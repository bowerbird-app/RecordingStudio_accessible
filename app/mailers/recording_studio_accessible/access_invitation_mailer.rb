# frozen_string_literal: true

module RecordingStudioAccessible
  class AccessInvitationMailer < (defined?(::ApplicationMailer) ? ::ApplicationMailer : ActionMailer::Base)
    helper RecordingStudioAccessible::CopyHelper if respond_to?(:helper)

    def accessible_t(...)
      Copy.t(...)
    end

    def access_invitation
      I18n.with_locale(mailer_locale) do
        assign_invitation_details
        mail(from: resolved_from_address, to: @email, subject: invitation_subject)
      end
    end

    private

    def assign_invitation_details
      @email = params[:email].to_s
      @recording = params[:recording]
      @recording_label = AccessGrantedMailer.recordable_label_for(@recording)
      assign_invitation_role_and_links
    end

    def assign_invitation_role_and_links
      @role = params[:role].to_s
      @role_label = Copy.role_name(@role).downcase
      @manager_actor_display_name = AccessGrantedMailer.display_label_for(params[:manager_actor])
      @acceptance_url = params[:acceptance_url]
    end

    def invitation_subject
      params[:subject].presence || Copy.t("mailers.invitation.subject")
    end

    def mailer_locale
      params[:locale].presence || I18n.locale
    end

    def resolved_from_address
      self.class.default_params[:from].presence ||
        ActionMailer::Base.default_params[:from].presence ||
        "no-reply@example.com"
    end
  end
end
