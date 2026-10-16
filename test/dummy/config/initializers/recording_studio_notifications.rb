# frozen_string_literal: true

# OTP delivery asks the notifications gem to send email and push. The dummy
# app records those deliveries in memory so tests can read the code back.
Rails.application.config.to_prepare do
  next unless defined?(RecordingStudioNotifications)

  adapter = Class.new do
    def deliver(notification:, delivery:)
      delivery.mark_delivered! if delivery.respond_to?(:mark_delivered!)
      notification
    end
  end.new

  RecordingStudioNotifications.register_channel(:email, adapter) unless RecordingStudioNotifications.channels.registered?(:email)
  RecordingStudioNotifications.register_channel(:push, adapter) unless RecordingStudioNotifications.channels.registered?(:push)
  RecordingStudioNotifications.configuration.deliver_later = false
end
