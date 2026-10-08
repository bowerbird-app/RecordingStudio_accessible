# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    module InviteKnownActor
      private

      def grant_known_actor(actor, manager)
        grant = grant_and_close_invitation(actor, manager)
        return grant unless grant&.success?

        notify_known_grant(actor, manager)
        success(AccessInvitation::Outcome.granted(access_recording: grant.value, notice: copy("flashes.access_granted")))
      end

      def grant_and_close_invitation(actor, manager)
        grant = nil
        @recording.transaction do
          grant = GrantRecordingAccess.call(
            recording: @recording,
            actor: actor,
            role: @role,
            manager_actor: manager,
            controller: @controller
          )
          raise ActiveRecord::Rollback unless grant.success?

          stamp_matching_invitation(actor)
        end
        grant
      end

      def notify_known_grant(actor, manager)
        configuration.notify_access_granted(
          controller: @controller,
          recording: @recording,
          actor: actor,
          role: @role,
          manager_actor: manager
        )
      end

      def stamp_matching_invitation(actor)
        return unless configuration.access_invitation_actor_matches?(actor: actor, email: @email)

        AccessInvitation.stamp_unclosed!(recording: @recording, email: @email, actor: actor)
      end
    end
  end
end
