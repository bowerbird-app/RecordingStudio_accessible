# frozen_string_literal: true

require "recording_studio_accessible/extracted/recording_studio/access_roles"

module RecordingStudioAccessible
  # Keeps at least one effective :admin on a recording that already has one.
  # Effective admin matches AccessGrantList / authorized?(:admin): a kept,
  # ranked admin grant on the recording or an ancestor. Pending invitations,
  # trashed grants, and dependents whose manager is invalid do not count.
  class LastAdminGuard
    class << self
      def protect!(recordings:, allow_last_admin_removal: false)
        lockable = Array(recordings).select { |recording| applicable?(recording) }
        return yield if lockable.empty?

        RecordingStudio::Recording.transaction do
          lock_in_id_order!(lockable)
          previously = previously_administered(lockable, allow_last_admin_removal)
          value = yield
          assert_still_administered!(previously)
          value
        end
      end

      def administered?(recording)
        return false unless recording

        AccessGrantList.rows_for(recording).any? do |row|
          RecordingStudio::AccessRoles.satisfies?(role: row.effective_role, minimum_role: :admin)
        end
      end

      def dependent_parent_recordings(access_recording)
        return [] unless access_recording.respond_to?(:id)

        DirectAccessQuery.access_recordings_depending_on(access_recording.id).filter_map(&:parent_recording)
      end

      private

      def lock_in_id_order!(recordings)
        recordings.sort_by { |recording| recording.id.to_s }.each(&:lock!)
      end

      def previously_administered(recordings, allow_last_admin_removal)
        return [] if allow_last_admin_removal

        recordings.select { |recording| administered?(recording) }
      end

      def assert_still_administered!(recordings)
        recordings.each do |recording|
          raise ::RecordingStudioAccessible::LastAdminError unless administered?(recording.reload)
        end
      end

      def applicable?(recording)
        return false unless recording
        return false unless defined?(::RecordingStudio::Recording)
        return false unless recording.is_a?(::RecordingStudio::Recording)

        recording.respond_to?(:persisted?) && recording.persisted?
      end
    end
  end
end
