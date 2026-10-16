# frozen_string_literal: true

module RecordingStudioAccessible
  class AccessRequestSubmittedNotifier
    def self.call(request_recording:, recording:, actor:, role:, controller: nil)
      new(
        request_recording: request_recording,
        recording: recording,
        actor: actor,
        role: role,
        controller: controller
      ).call
    end

    def initialize(request_recording:, recording:, actor:, role:, controller: nil)
      @request_recording = request_recording
      @recording = recording
      @actor = actor
      @role = role
      @controller = controller
    end

    def call
      reviewers.each { |reviewer| deliver(reviewer) }
    end

    private

    def reviewers
      AccessRequestReviewers.for(@recording).reject { |reviewer| same_actor?(reviewer, @actor) }
    end

    def deliver(reviewer)
      recipient = reviewer_email(reviewer)
      return if recipient.blank?

      locale = notification_locale(reviewer, recipient)
      I18n.with_locale(locale) { send_mail(reviewer, locale) }
    rescue StandardError
      nil
    end

    def reviewer_email(reviewer)
      return unless reviewer.respond_to?(:email)

      reviewer.email.to_s.strip
    end

    def notification_locale(reviewer, recipient)
      RecordingStudioAccessible.configuration.access_notification_locale_for(
        controller: @controller, recording: @recording, actor: reviewer, email: recipient, role: @role
      )
    end

    def send_mail(reviewer, locale)
      mail = AccessRequestSubmittedMailer.with(mail_params(reviewer, locale)).access_request_submitted
      deliver_mail(mail, locale)
    end

    def mail_params(reviewer, locale)
      {
        request_recording: @request_recording, recording: @recording, actor: @actor, role: @role,
        reviewer: reviewer, locale: locale, review_url: review_url
      }
    end

    def review_url
      return if @controller.blank? || !@controller.respond_to?(:recording_access_requests_url)

      options = url_options
      return if options.blank?

      @controller.recording_access_requests_url(@recording, **options)
    rescue StandardError
      nil
    end

    def url_options
      request = controller_request
      return {} unless request

      { host: request.host, protocol: request.protocol }.merge(optional_url_options(request))
    rescue StandardError
      {}
    end

    def controller_request
      return unless @controller.respond_to?(:request)

      @controller.request
    end

    def optional_url_options(request)
      options = {}
      options[:port] = request.port if include_port?(request)
      script_name = request.script_name if request.respond_to?(:script_name)
      options[:script_name] = script_name if script_name.present?
      options
    end

    def include_port?(request)
      request.respond_to?(:port) && request.port.present?
    end

    def deliver_mail(mail, locale)
      return unless mail

      I18n.with_locale(locale) do
        mail.respond_to?(:deliver_now) ? mail.deliver_now : mail.deliver_later
      end
    end

    def same_actor?(left, right)
      return false unless left && right
      return true if left.equal?(right)
      return false unless left.respond_to?(:id) && right.respond_to?(:id)

      ActorType.for(left) == ActorType.for(right) && left.id == right.id
    end
  end
end
