# frozen_string_literal: true

module RecordingStudioAccessible
  class AccessRequestSubmittedMailer < (defined?(::ApplicationMailer) ? ::ApplicationMailer : ActionMailer::Base)
    helper RecordingStudioAccessible::CopyHelper if respond_to?(:helper)

    def accessible_t(...)
      Copy.t(...)
    end

    def access_request_submitted
      I18n.with_locale(params[:locale].presence || I18n.locale) do
        @recording = params[:recording]
        @recording_label = AccessGrantedMailer.recordable_label_for(@recording)
        @actor = params[:actor]
        @requester = AccessGrantedMailer.display_label_for(@actor)
        @role_label = Copy.role_name(params[:role]).downcase
        @reviewer = params[:reviewer]
        @greeting_email = @reviewer.respond_to?(:email) ? @reviewer.email.to_s : ""
        @message = params[:request_recording]&.recordable&.message
        @review_url = params[:review_url]
        @text_body_key = body_key(html: false)
        @html_body_key = body_key(html: true)

        mail(
          from: resolved_from_address,
          to: @greeting_email,
          subject: subject_line
        )
      end
    end

    private

    def body_key(html:)
      prefix = html ? "body_html" : "body"
      return "mailers.access_request.#{prefix}" if @role_label.present? && @recording_label.present?
      return "mailers.access_request.#{prefix}_without_role" if @recording_label.present?
      return "mailers.access_request.#{prefix}_without_recording" if @role_label.present?

      "mailers.access_request.#{prefix}_without_role_or_recording"
    end

    def subject_line
      if @recording_label.present?
        Copy.t("mailers.access_request.subject_with_recording", recording: @recording_label)
      else
        Copy.t("mailers.access_request.subject")
      end
    end

    def resolved_from_address
      self.class.default_params[:from].presence ||
        ActionMailer::Base.default_params[:from].presence ||
        "no-reply@example.com"
    end
  end
end
