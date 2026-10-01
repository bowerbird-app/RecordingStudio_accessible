# frozen_string_literal: true

require "digest"
require "securerandom"

module RecordingStudioAccessible
  class AccessInvitation < ActiveRecord::Base
    self.table_name = "recording_studio_access_invitations"

    EMAIL_FORMAT = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

    belongs_to :recording, class_name: "RecordingStudio::Recording"
    belongs_to :manager_actor, polymorphic: true
    belongs_to :accepted_by_actor, polymorphic: true, optional: true

    scope :open, -> { where(accepted_at: nil, revoked_at: nil) }

    validates :email, :role, :token_digest, :expires_at, :last_sent_at, presence: true
    validates :token_digest, uniqueness: true
    validate :email_is_normalized
    validate :role_is_grantable
    validate :recording_and_email_are_immutable, on: :update
    validate :accepted_and_revoked_are_exclusive

    class Outcome
      attr_reader :access_recording, :notice, :pending

      def self.granted(access_recording: nil, notice: "Access granted.")
        new(kind: :granted, access_recording: access_recording, notice: notice)
      end

      def self.invited(pending:, notice: "Invitation sent.")
        new(kind: :invited, pending: pending, notice: notice)
      end

      def self.revoked(notice: "Invitation revoked.")
        new(kind: :revoked, notice: notice)
      end

      def initialize(kind:, access_recording: nil, notice: nil, pending: nil)
        @kind = kind
        @access_recording = access_recording
        @notice = notice
        @pending = pending
      end

      def granted?
        @kind == :granted
      end

      def invited?
        @kind == :invited
      end

      def revoked?
        @kind == :revoked
      end
    end

    class PendingInvitation
      attr_reader :id, :email, :role, :expires_at, :last_sent_at, :expired

      def self.from(invitation)
        new(
          id: invitation.id,
          email: invitation.email,
          role: invitation.role,
          expires_at: invitation.expires_at,
          last_sent_at: invitation.last_sent_at,
          expired: invitation.expired?
        )
      end

      def initialize(attrs)
        @id = attrs[:id]
        @email = attrs[:email]
        @role = attrs[:role]
        @expires_at = attrs[:expires_at]
        @last_sent_at = attrs[:last_sent_at]
        @expired = attrs[:expired]
      end
    end

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

        open.where(recording_id: recording.id).order(:email).map { |invitation| PendingInvitation.from(invitation) }
      end

      def invite(recording:, email:, role:, manager_actor: nil, controller: nil)
        normalized_email = normalize_email(email)
        email_problem = email_problem_for(normalized_email)
        return failure(email_problem) if email_problem

        continue_invite(recording, normalized_email, role, manager_actor, controller)
      end

      def accept(invitation:, actor:, controller: nil)
        error = accept_precondition_error(invitation, actor, controller)
        return failure(error) if error

        accept_with_lock(invitation, actor)
      rescue ActiveRecord::RecordNotFound
        failure("Invitation was not found")
      end

      def revoke(invitation:, manager_actor:)
        return failure("Invitation was not found") if invitation.nil?

        result = nil
        invitation.with_lock do
          result = revoke_locked(invitation, manager_actor)
        end
        result
      rescue ActiveRecord::RecordNotFound
        failure("Invitation was not found")
      end

      private

      def configuration
        RecordingStudioAccessible.configuration
      end

      def failure(error)
        Services::BaseService::Result.new(success: false, error: error.to_s)
      end

      def success(value)
        Services::BaseService::Result.new(success: true, value: value)
      end

      def email_problem_for(email)
        return "Email is required" if email.blank?
        return "Email is invalid" unless email.match?(EMAIL_FORMAT)

        nil
      end

      def invite_gate_problem(recording, role, manager, controller)
        return "Recording is required" unless persisted_recording?(recording)
        return "Not authorized to manage access" unless manager_allowed?(recording, manager, controller)
        return SharedRootAccess::GRANT_DENIED_MESSAGE if SharedRootAccess.target?(recording)
        unless Compatibility.access_management_allowed?(recording)
          return "Direct access is not enabled for this recording"
        end
        return "Role is invalid" unless grantable_role?(role)

        nil
      end

      def persisted_recording?(recording)
        recording.present? && recording.respond_to?(:id) && recording.id.present?
      end

      def manager_allowed?(recording, manager, controller)
        AccessManagementPolicy.allowed?(recording: recording, actor: manager, controller: controller)
      end

      def grantable_role?(role)
        return false unless defined?(::RecordingStudio::Access)

        ::RecordingStudio::Access.roles.key?(role.to_s)
      end

      def continue_invite(recording, email, role, manager_actor, controller)
        manager = manager_actor || configuration.current_actor_for(controller: controller)
        gate_problem = invite_gate_problem(recording, role, manager, controller)
        return failure(gate_problem) if gate_problem

        invite_for_actor(recording, email, role, manager, controller)
      end

      def invite_for_actor(recording, email, role, manager, controller)
        actor = configuration.resolve_actor_for_email(controller: controller, email: email)
        return invite_unknown(recording, email, role, manager, controller) unless actor

        context = { role: role, manager: manager, controller: controller }
        grant_known_actor(recording, email, actor, context)
      end

      def accept_with_lock(invitation, actor)
        result = nil
        invitation.with_lock do
          result = accept_locked(invitation, actor)
          raise ActiveRecord::Rollback if result.failure?
        end
        result
      end

      def grant_known_actor(recording, email, actor, context)
        grant = grant_and_close_invitation(recording, email, actor, context)
        return grant unless grant&.success?

        notify_known_grant(recording, actor, context)
        success(Outcome.granted(access_recording: grant.value, notice: "Access granted."))
      end

      def grant_and_close_invitation(recording, email, actor, context)
        grant = nil
        recording.transaction do
          grant = call_grant(recording, actor, context)
          raise ActiveRecord::Rollback unless grant.success?

          stamp_open_invitation(recording, email, actor)
        end
        grant
      end

      def call_grant(recording, actor, context)
        Services::GrantRecordingAccess.call(
          recording: recording,
          actor: actor,
          role: context[:role],
          manager_actor: context[:manager],
          controller: context[:controller]
        )
      end

      def notify_known_grant(recording, actor, context)
        configuration.notify_access_granted(
          controller: context[:controller],
          recording: recording,
          actor: actor,
          role: context[:role],
          manager_actor: context[:manager]
        )
      end

      def stamp_open_invitation(recording, email, actor)
        return unless configuration.access_invitation_actor_matches?(actor: actor, email: email)

        invitation = open.find_by(recording_id: recording.id, email: email)
        return unless invitation

        invitation.with_lock do
          next unless invitation.open?

          invitation.update!(accepted_at: Time.current, accepted_by_actor: actor)
        end
      end

      def invite_unknown(recording, email, role, manager, controller)
        invitation, raw_token = write_open_invitation(recording, email, role, manager)
        details = { email: email, role: role, manager: manager, raw_token: raw_token }
        send_invitation(controller, recording, details)
        success(Outcome.invited(pending: PendingInvitation.from(invitation)))
      rescue ActiveRecord::RecordNotUnique
        failure("Invitation could not be saved")
      end

      def send_invitation(controller, recording, details)
        configuration.deliver_access_invitation(
          controller: controller,
          recording: recording,
          email: details[:email],
          role: details[:role].to_s,
          manager_actor: details[:manager],
          raw_token: details[:raw_token]
        )
      end

      def write_open_invitation(recording, email, role, manager)
        attempts = 0
        begin
          attempts += 1
          insert_or_refresh_open_invitation(recording, email, role, manager)
        rescue ActiveRecord::RecordNotUnique
          retry if attempts < 2

          raise
        end
      end

      def insert_or_refresh_open_invitation(recording, email, role, manager)
        raw_token = fresh_invitation_token
        invitation = save_open_invitation(recording, email, role, manager, raw_token)
        [invitation, raw_token]
      end

      def fresh_invitation_token
        # Keyword padding: is a Hash on Ruby 3.3, which turns padding on and fails the token route.
        SecureRandom.urlsafe_base64(32, false)
      end

      def save_open_invitation(recording, email, role, manager, raw_token)
        now = Time.current
        attributes = open_invitation_attributes(role, manager, raw_token, now)
        recording.transaction do
          recording.lock!
          refresh_or_create_open_invitation(recording, email, attributes)
        end
      end

      def open_invitation_attributes(role, manager, raw_token, now)
        {
          role: role.to_s,
          manager_actor: manager,
          token_digest: Digest::SHA256.hexdigest(raw_token),
          expires_at: now + configuration.access_invitation_ttl,
          last_sent_at: now
        }
      end

      def refresh_or_create_open_invitation(recording, email, attributes)
        invitation = open.find_by(recording_id: recording.id, email: email)
        return update_open_invitation(invitation, attributes) if invitation

        create!(attributes.merge(recording: recording, email: email))
      end

      def update_open_invitation(invitation, attributes)
        invitation.update!(attributes)
        invitation
      end

      def accept_precondition_error(invitation, actor, _controller)
        return "Invitation was not found" if invitation.nil?
        return "Sign in to accept this invitation" if actor.nil?
        return "This invitation was sent to a different email" unless actor_matches?(actor, invitation.email)

        nil
      end

      def accept_locked(invitation, actor)
        return failure("This invitation was sent to a different email") unless actor_matches?(actor, invitation.email)
        return accept_existing(invitation, actor) if invitation.accepted?
        return failure("Invitation was revoked") if invitation.revoked?
        return failure("Invitation has expired") unless invitation.acceptable?
        return failure("Not authorized to manage access") unless manager_still_allowed?(invitation)

        grant_and_stamp(invitation, actor)
      end

      def accept_existing(invitation, actor)
        access_recording = DirectAccessQuery.access_recordings_for_actor(
          recording: invitation.recording,
          actor: actor
        ).first
        notice = access_recording ? "Access granted." : "Invitation already accepted."
        success(Outcome.granted(access_recording: access_recording, notice: notice))
      end

      def manager_still_allowed?(invitation)
        AccessManagementPolicy.allowed?(recording: invitation.recording, actor: invitation.manager_actor)
      end

      def grant_and_stamp(invitation, actor)
        grant = Services::GrantRecordingAccess.call(
          recording: invitation.recording,
          actor: actor,
          role: invitation.role,
          manager_actor: invitation.manager_actor
        )
        return grant unless grant.success?

        invitation.update!(accepted_at: Time.current, accepted_by_actor: actor)
        success(Outcome.granted(access_recording: grant.value, notice: "Access granted."))
      end

      def actor_matches?(actor, email)
        configuration.access_invitation_actor_matches?(actor: actor, email: email)
      end

      def revoke_locked(invitation, manager_actor)
        unless AccessManagementPolicy.allowed?(recording: invitation.recording, actor: manager_actor)
          return failure("Not authorized to manage access")
        end
        return failure("Invitation has already been accepted") if invitation.accepted?
        return success(Outcome.revoked) if invitation.revoked?

        invitation.update!(revoked_at: Time.current)
        success(Outcome.revoked)
      end
    end

    def accepted?
      accepted_at.present?
    end

    def revoked?
      revoked_at.present?
    end

    def open?
      accepted_at.nil? && revoked_at.nil?
    end

    def expired?
      expires_at.blank? || expires_at <= Time.current
    end

    def acceptable?
      open? && expires_at.present? && expires_at > Time.current
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
