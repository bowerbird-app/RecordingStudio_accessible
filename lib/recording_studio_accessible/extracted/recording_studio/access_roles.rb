# frozen_string_literal: true

require "recording_studio_accessible/role_registry"

module RecordingStudio
  module AccessRoles
    # Built-in order when no recordable declares a custom role.
    # Live ranks, including declared custom roles, live on RoleRegistry.
    ORDER = { "view" => 0, "edit" => 1, "admin" => 2 }.freeze

    class << self
      def value_for(role, recording: nil)
        return RecordingStudioAccessible::RoleRegistry.rank_on(recording, role) if recording

        RecordingStudioAccessible::RoleRegistry.global_rank(role)
      end

      def satisfies?(role:, minimum_role:, recording: nil)
        return RecordingStudioAccessible::RoleRegistry.meets?(recording, role, minimum_role) if recording

        role_value = value_for(role)
        minimum_value = value_for(minimum_role)
        return false unless role_value && minimum_value

        role_value >= minimum_value
      end

      def names_at_or_above(minimum_role)
        RecordingStudioAccessible::RoleRegistry.names_at_or_above(minimum_role)
      end

      def normalize(role)
        role&.to_s
      end

      # Strongest ranked name in the list. Unranked names are ignored.
      # Pass recording so a role counts only when that type lists it.
      # Empty and all-unranked lists return nil.
      def strongest(roles, recording: nil)
        ranked = Array(roles).select { |role| value_for(role, recording: recording) }
        ranked.max_by { |role| value_for(role, recording: recording) }
      end
    end
  end
end
