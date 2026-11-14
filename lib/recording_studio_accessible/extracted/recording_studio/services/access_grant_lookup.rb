# frozen_string_literal: true

module RecordingStudio
  module Services
    class AccessGrantLookup
      def initialize(actor:, recordings:, access_recordings: nil)
        @actor = actor
        @recordings = Array(recordings).compact
        @access_recordings = access_recordings
      end

      def role_for(recording)
        RecordingStudio::AccessRoles.strongest(roles_for(recording))
      end

      def roles_for(recording)
        Array(roles_by_parent_id[recording&.id])
      end

      private

      attr_reader :actor, :recordings, :access_recordings

      def roles_by_parent_id
        @roles_by_parent_id ||= load_roles_by_parent_id
      end

      def load_roles_by_parent_id
        return {} unless actor && (recordings.any? || access_recordings)

        grant_rows.each_with_object({}) do |access_recording, roles|
          store_role(roles, access_recording)
        end
      end

      def grant_rows
        return access_recordings unless access_recordings.nil?

        RecordingStudioAccessible::DirectAccessQuery.access_recordings_for_actor_in(
          recordings: recordings,
          actor: actor
        )
      end

      def store_role(roles, access_recording)
        role = access_recording.recordable&.role.to_s.strip
        return if role.empty?
        return unless RecordingStudioAccessible::DependentAccess.effective?(access_recording)

        parent_id = access_recording.parent_recording_id
        bucket = (roles[parent_id] ||= [])
        bucket << role unless bucket.include?(role)
      end
    end
  end
end
