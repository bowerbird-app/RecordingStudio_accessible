# frozen_string_literal: true

module RecordingStudioAccessible
  # Keeps at least one effective :admin on a recording that already has one.
  # Effective admin matches actors_with_access / authorized?(:admin): a kept,
  # ranked admin grant on the recording or an ancestor. Pending invitations,
  # trashed grants, and dependents whose manager is invalid do not count.
  class LastAdminGuard
    class << self
      def protect!(recordings:, allow_last_admin_removal: false)
        lockable = Array(recordings).select { |recording| applicable?(recording) }
        return yield if lockable.empty?

        RecordingStudio::Recording.transaction do
          lock_in_id_order!(lockable)
          lookups = admin_lookups(lockable, allow_last_admin_removal)
          previously = previously_administered(lockable, lookups, allow_last_admin_removal)
          value = yield
          assert_still_administered!(previously, lookups)
          value
        end
      end

      def administered?(recording)
        return false unless recording

        ActorsWithAccess.new(recording).any_actor?(minimum_role: :admin)
      end

      def dependent_parent_recordings(access_recording)
        return [] unless access_recording.respond_to?(:id)

        DirectAccessQuery.access_recordings_depending_on(access_recording.id).filter_map(&:parent_recording)
      end

      private

      def lock_in_id_order!(recordings)
        recordings.sort_by { |recording| recording.id.to_s }.each(&:lock!)
      end

      def admin_lookups(recordings, allow_last_admin_removal)
        return {} if allow_last_admin_removal

        recordings.to_h { |recording| [recording.id, ActorsWithAccess.new(recording)] }
      end

      def previously_administered(recordings, lookups, allow_last_admin_removal)
        return [] if allow_last_admin_removal

        recordings.select { |recording| lookups.fetch(recording.id).any_actor?(minimum_role: :admin) }
      end

      # The same lookup is refreshed after the write. Locks are still held, so
      # another transaction cannot remove the remaining admin before we commit.
      # Refresh reads grants again with the query cache off; it does not reuse
      # the pre-write answer.
      def assert_still_administered!(recordings, lookups)
        recordings.each do |recording|
          recording.reload
          lookup = lookups.fetch(recording.id)
          lookup.refresh!
          raise ::RecordingStudioAccessible::LastAdminError unless lookup.any_actor?(minimum_role: :admin)
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
