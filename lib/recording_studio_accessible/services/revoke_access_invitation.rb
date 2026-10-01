# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class RevokeAccessInvitation < BaseService
      def initialize(invitation:, manager_actor:)
        @invitation = invitation
        @manager_actor = manager_actor
      end

      private

      def perform
        return failure("Invitation was not found") if @invitation.nil?

        result = nil
        @invitation.with_lock do
          result = revoke_locked
        end
        result
      rescue ActiveRecord::RecordNotFound
        failure("Invitation was not found")
      end

      def service_args
        {
          invitation_id: @invitation&.id,
          manager_actor_gid: global_id_string_for(@manager_actor)
        }
      end

      def revoke_locked
        unless AccessManagementPolicy.allowed?(recording: @invitation.recording, actor: @manager_actor)
          return failure("Not authorized to manage access")
        end
        return failure("Invitation has already been accepted") if @invitation.accepted?
        return success(AccessInvitation::Outcome.revoked) if @invitation.revoked?

        @invitation.update!(revoked_at: Time.current)
        success(AccessInvitation::Outcome.revoked)
      end
    end
  end
end
