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

      def replace_unclosed!(recording:, email:, role:, manager_actor:, raw_token:)
        recording.transaction do
          recording.lock!
          upsert_unclosed!(recording, email, unclosed_attributes(role, manager_actor, raw_token))
        end
      end

      def stamp_unclosed!(recording:, email:, actor:)
        invitation = unclosed.find_by(recording_id: recording.id, email: email)
        return unless invitation

        invitation.with_lock do
          next unless invitation.unclosed?

          invitation.update!(accepted_at: Time.current, accepted_by_actor: actor)
        end
      end

      private

      def upsert_unclosed!(recording, email, attributes)
        existing = unclosed.find_by(recording_id: recording.id, email: email)
        return refresh_unclosed!(existing, attributes) if existing

        create!(attributes.merge(recording: recording, email: email))
      end

      def refresh_unclosed!(invitation, attributes)
        invitation.update!(attributes)
        invitation
      end

      def unclosed_attributes(role, manager_actor, raw_token)
        now = Time.current
        {
          role: role.to_s,
          manager_actor: manager_actor,
          token_digest: Digest::SHA256.hexdigest(raw_token),
          expires_at: now + RecordingStudioAccessible.configuration.access_invitation_ttl,
          last_sent_at: now
        }
      end
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

      errors.add(:email, "must be normalized")
    end

    def role_is_grantable
      return if role.blank?
      return if defined?(::RecordingStudio::Access) && ::RecordingStudio::Access.roles.key?(role.to_s)

      errors.add(:role, "is invalid")
    end

    def recording_and_email_are_immutable
      errors.add(:recording_id, "cannot change") if will_save_change_to_recording_id?
      errors.add(:email, "cannot change") if will_save_change_to_email?
    end

    def accepted_and_revoked_are_exclusive
      return if accepted_at.blank? || revoked_at.blank?

      errors.add(:base, "cannot be accepted and revoked")
    end
  end
end
