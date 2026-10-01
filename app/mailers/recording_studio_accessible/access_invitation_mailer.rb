# frozen_string_literal: true

module RecordingStudioAccessible
  class AccessInvitationMailer < (defined?(::ApplicationMailer) ? ::ApplicationMailer : ActionMailer::Base)
    def access_invitation
      assign_invitation_details
      mail(from: resolved_from_address, to: @email, subject: invitation_subject)
    end

    private

    def assign_invitation_details
      @email = params[:email].to_s
      @recording = params[:recording]
      @recording_label = AccessGrantedMailer.recordable_label_for(@recording)
      @role = params[:role].to_s
      @manager_actor_display_name = AccessGrantedMailer.display_label_for(params[:manager_actor])
      @acceptance_url = params[:acceptance_url]
    end

    def invitation_subject
      params[:subject].presence || "You were invited"
    end

    def resolved_from_address
      self.class.default_params[:from].presence ||
        ActionMailer::Base.default_params[:from].presence ||
        "no-reply@example.com"
    end
  end
end
