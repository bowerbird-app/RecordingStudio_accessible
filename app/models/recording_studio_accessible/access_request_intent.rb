# frozen_string_literal: true

module RecordingStudioAccessible
  class AccessRequestIntent < ActiveRecord::Base
    self.table_name = "recording_studio_access_request_intents"

    LIFETIME = 24.hours
    ACTION_MAX = 120
    NAME_MAX = 120

    validates :recording_id, :user_id, :otp_challenge_id, :email, :expires_at, presence: true
    validates :email, length: { maximum: 255 }
    validates :role, length: { maximum: 64 }, allow_nil: true
    validates :action, length: { maximum: ACTION_MAX }, allow_nil: true
    validates :submitted_name, length: { maximum: NAME_MAX }, allow_nil: true

    def fulfilled?
      fulfilled_at.present?
    end

    def expired?
      expires_at <= Time.current
    end

    def open?
      !expired?
    end
  end
end
