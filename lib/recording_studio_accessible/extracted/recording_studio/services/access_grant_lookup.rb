# frozen_string_literal: true

module RecordingStudio
  module Services
    class AccessGrantLookup
      def initialize(actor:, recordings:)
        @actor = actor
        @recordings = Array(recordings).compact
      end

      def role_for(recording)
        roles_by_parent_id[recording&.id]
      end

      private

      attr_reader :actor, :recordings

      def roles_by_parent_id
        @roles_by_parent_id ||= load_roles_by_parent_id
      end

      def load_roles_by_parent_id
        return {} unless actor && recordings.any?

        RecordingStudioAccessible::DirectAccessQuery.access_recordings_for_actor_in(
          recordings: recordings,
          actor: actor
        ).each_with_object({}) do |access_recording, roles|
          store_stronger_role(roles, access_recording)
        end
      end

      def store_stronger_role(roles, access_recording)
        role = access_recording.recordable&.role
        return unless RecordingStudio::AccessRoles.value_for(role)

        parent_id = access_recording.parent_recording_id
        current_role = roles[parent_id]
        roles[parent_id] = role if stronger_role?(role, current_role)
      end

      def stronger_role?(role, current_role)
        current_role.nil? || RecordingStudio::AccessRoles.value_for(role) >
          RecordingStudio::AccessRoles.value_for(current_role)
      end
    end
  end
end
