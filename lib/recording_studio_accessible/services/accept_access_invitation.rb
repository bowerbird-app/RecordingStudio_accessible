# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class AcceptAccessInvitation < BaseService
      def initialize(invitation:, actor:, controller: nil)
        @invitation = invitation
        @actor = actor
        @controller = controller
      end

      private

      def perform
        error = precondition_error
        return failure(error) if error

        accept_with_lock
      rescue ActiveRecord::RecordNotFound
        failure(copy("errors.invitation_not_found"))
      end

      def service_args
        {
          invitation_id: @invitation&.id,
          actor_gid: global_id_string_for(@actor),
          controller_present: !@controller.nil?
        }
      end

      def precondition_error
        return copy("errors.invitation_not_found") if @invitation.nil?
        return copy("flashes.sign_in_to_accept") if @actor.nil?
        return copy("errors.invitation_wrong_email") unless actor_matches?

        nil
      end

      def accept_with_lock
        result = nil
        @invitation.with_lock do
          result = accept_locked
          raise ActiveRecord::Rollback if result.failure?
        end
        result
      end

      def accept_locked
        return failure(copy("errors.invitation_wrong_email")) unless actor_matches?
        return accept_existing if @invitation.accepted?
        return failure(copy("errors.invitation_revoked")) if @invitation.revoked?
        return failure(copy("errors.invitation_expired")) unless @invitation.acceptable?
        return failure(copy("errors.not_authorized")) unless manager_still_allowed?

        grant_and_stamp
      end

      def accept_existing
        access_recording = DirectAccessQuery.access_recordings_for_actor(
          recording: @invitation.recording,
          actor: @actor
        ).first
        notice = access_recording ? copy("flashes.access_granted") : copy("flashes.invitation_already_accepted")
        success(AccessInvitation::Outcome.granted(access_recording: access_recording, notice: notice))
      end

      def manager_still_allowed?
        AccessManagementPolicy.allowed?(recording: @invitation.recording, actor: @invitation.manager_actor)
      end

      def grant_and_stamp
        grant = GrantRecordingAccess.call(
          recording: @invitation.recording,
          actor: @actor,
          role: @invitation.role,
          manager_actor: @invitation.manager_actor
        )
        return grant unless grant.success?

        @invitation.update!(accepted_at: Time.current, accepted_by_actor: @actor)
        success(AccessInvitation::Outcome.granted(access_recording: grant.value, notice: copy("flashes.access_granted")))
      end

      def actor_matches?
        RecordingStudioAccessible.configuration.access_invitation_actor_matches?(
          actor: @actor,
          email: @invitation.email
        )
      end
    end
  end
end
