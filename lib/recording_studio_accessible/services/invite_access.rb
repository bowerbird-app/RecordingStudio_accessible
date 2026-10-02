# frozen_string_literal: true

require "securerandom"

module RecordingStudioAccessible
  module Services
    class InviteAccess < BaseService
      include AccessRecordLifecycle
      include InviteKnownActor
      include InviteUnclosed

      def initialize(recording:, email:, role:, manager_actor: nil, controller: nil)
        @recording = recording
        @email = AccessInvitation.normalize_email(email)
        @role = role.to_s.strip
        @manager_actor = manager_actor
        @controller = controller
      end

      private

      def perform
        problem = email_problem
        return failure(problem) if problem

        manager = effective_manager_actor(manager_actor: @manager_actor, controller: @controller)
        gate = management_gate(manager)
        return gate if gate

        actor = configuration.resolve_actor_for_email(controller: @controller, email: @email)
        return grant_known_actor(actor, manager) if actor

        invite_unknown(manager)
      end

      def service_args
        {
          recording_id: @recording&.id,
          email: @email,
          role: @role.to_s,
          manager_actor_gid: global_id_string_for(@manager_actor)
        }
      end

      def configuration
        RecordingStudioAccessible.configuration
      end

      def email_problem
        return "Email is required" if @email.blank?
        return "Email is invalid" unless @email.match?(AccessInvitation::EMAIL_FORMAT)

        nil
      end

      def management_gate(manager)
        return failure("Recording is required") unless persisted_recording?

        target = validate_access_management_target!(@recording, manager_actor: manager, controller: @controller)
        return target unless target == true
        return failure("Role is invalid") unless grantable_role?

        nil
      end

      def persisted_recording?
        @recording.present? && @recording.respond_to?(:id) && @recording.id.present?
      end

      def grantable_role?
        RecordingStudioAccessible.role_valid_for?(@recording, @role)
      end

      def deliver_invitation(manager, raw_token)
        configuration.deliver_access_invitation(
          controller: @controller,
          recording: @recording,
          email: @email,
          role: @role.to_s,
          manager_actor: manager,
          raw_token: raw_token
        )
      end

      def fresh_invitation_token
        SecureRandom.urlsafe_base64(32)
      end
    end
  end
end
