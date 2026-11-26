# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    module SelfDelegatedGrant
      private

      def validate_self_delegated_target!
        target_result = validate_grant_target!(@recording)
        return target_result unless target_result == true

        held = RecordingStudioAccessible.role_for(actor: manager_actor, recording: @recording)
        return failure(copy("errors.self_delegated_not_a_member")) if held.blank?
        return failure(copy("errors.self_delegated_role_not_allowed")) unless self_delegated_role_allowed?(held)

        true
      end

      def self_delegated_role_allowed?(held)
        return false unless RoleCeiling.allowed?(recording: @recording, manager: manager_actor, role: @role)

        held_name = held.to_s
        requested = @role.to_s.strip
        return true if held_name == requested
        return true if RecordingStudio::AccessRoles.satisfies?(
          role: held, minimum_role: requested, recording: @recording
        )

        held_name == "admin"
      end
    end
  end
end
