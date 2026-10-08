# frozen_string_literal: true

require "digest"

module RecordingStudioAccessible
  class AccessInvitation < ActiveRecord::Base
    self.table_name = "recording_studio_access_invitations"

    EMAIL_FORMAT = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

    belongs_to :recording, class_name: "RecordingStudio::Recording"
    belongs_to :manager_actor, polymorphic: true
    belongs_to :accepted_by_actor, polymorphic: true, optional: true

    scope :unclosed, -> { where(accepted_at: nil, revoked_at: nil) }

    validates :email, :role, :token_digest, :expires_at, :last_sent_at, presence: true
    validates :token_digest, uniqueness: true
    validate :email_is_normalized
    validate :role_is_grantable
    validate :recording_and_email_are_immutable, on: :update
    validate :accepted_and_revoked_are_exclusive

    class << self
      def normalize_email(email)
        email.to_s.strip.downcase
      end

      def locate(raw_token)
        token = raw_token.to_s
        return if token.blank?

        find_by(token_digest: Digest::SHA256.hexdigest(token))
      end

      def pending_rows_for(recording)
        return [] if recording.blank? || recording.id.blank?

        unclosed.where(recording_id: recording.id).order(:email).map { |invitation| PendingInvitation.from(invitation) }
      end

      def stamp_unclosed!(recording:, email:, actor:)
        invitation = unclosed.find_by(recording_id: recording.id, email: email)
        return unless invitation

        invitation.with_lock do
          next unless invitation.unclosed?

          invitation.update!(accepted_at: Time.current, accepted_by_actor: actor)
        end
      end

      include Writes
    end

    def accepted?
      accepted_at.present?
    end

    def revoked?
      revoked_at.present?
    end

    def unclosed?
      accepted_at.nil? && revoked_at.nil?
    end

    def expired?
      expires_at.blank? || expires_at <= Time.current
    end

    def acceptable?
      unclosed? && expires_at.present? && expires_at > Time.current
    end

    def state
      return "accepted" if accepted?
      return "revoked" if revoked?
      return "expired" if expired?

      "pending"
    end

    private

    def email_is_normalized
      return if email.blank?
      return if email == self.class.normalize_email(email)

      errors.add(:email, :not_normalized, message: Copy.t("errors.email_not_normalized"))
    end

    def role_is_grantable
      return if role.blank?
      return if RecordingStudioAccessible.role_valid_for?(recording, role)

      errors.add(:role, :invalid, message: Copy.t("errors.role_invalid"))
    end

    def recording_and_email_are_immutable
      if will_save_change_to_recording_id?
        errors.add(:recording_id, :immutable, message: Copy.t("errors.cannot_change"))
      end
      errors.add(:email, :immutable, message: Copy.t("errors.cannot_change")) if will_save_change_to_email?
    end

    def accepted_and_revoked_are_exclusive
      return if accepted_at.blank? || revoked_at.blank?

      errors.add(:base, :accepted_and_revoked, message: Copy.t("errors.accepted_and_revoked"))
    end
  end
end
