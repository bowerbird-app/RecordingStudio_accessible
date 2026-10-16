# frozen_string_literal: true

require "recording_studio_accessible/extracted/recording_studio/access_roles"

module RecordingStudioAccessible
  # A manager can grant a role they hold or a weaker ranked role.
  # An admin can grant any role that recording accepts, including unranked ones.
  module RoleCeiling
    module_function

    def cap(roles, recording:, manager:)
      return roles if manager.nil?

      Array(roles).select { |role| allowed?(recording: recording, manager: manager, role: role) }
    end

    def allowed?(recording:, manager:, role:)
      held = held_role(recording, manager)
      requested = role.to_s.strip
      return false if held.blank? || requested.blank?
      return true if held == requested
      return true if RecordingStudio::AccessRoles.satisfies?(role: held, minimum_role: requested)

      held == "admin" && RecordingStudioAccessible.role_valid_for?(recording, requested)
    end

    def held_role(recording, manager)
      RecordingStudioAccessible.role_for(actor: manager, recording: recording).to_s
    end
  end
end
