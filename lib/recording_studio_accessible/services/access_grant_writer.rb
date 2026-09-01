# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    # Shared create/upsert path for direct Access grants.
    # Used by GrantRecordingAccess and BootstrapOwnerAccess so bootstrap
    # never invents a parallel Access write.
    module AccessGrantWriter
      private

      def upsert_access_recording!
        RecordingStudio::Recording.transaction do
          lock_grant_scope!

          existing_recordings = existing_access_recordings.to_a
          access_recording = existing_recordings.first

          if access_recording
            update_existing_access_recording(access_recording, existing_recordings)
          else
            create_access_recording
          end
        end
      end

      def update_existing_access_recording(access_recording, existing_recordings)
        deduplicate_access_recordings!(existing_recordings.drop(1))

        RecordingStudioAccessible::AccessCreationContext.allow do
          root_recording.revise(access_recording, actor: manager_actor) do |access|
            access.role = @role
            assign_depends_on(access)
          end
        end
      end

      def create_access_recording
        RecordingStudioAccessible::AccessCreationContext.allow do
          root_recording.record(
            RecordingStudio::Access,
            actor: manager_actor,
            parent_recording: @recording
          ) do |access|
            access.actor = @actor
            access.role = @role
            assign_depends_on(access)
          end
        end
      end

      def assign_depends_on(access)
        return unless @depends_on
        return unless access.respond_to?(:depends_on_recording_id=)

        access.depends_on_recording_id = @depends_on.id
      end

      def root_recording
        RecordingStudio.root_recording_or_self(@recording)
      end

      def lock_grant_scope!
        @recording.lock!
      end

      def existing_access_recordings
        return RecordingStudio::Recording.none unless @actor

        RecordingStudioAccessible::DirectAccessQuery.access_recordings_for_actor(
          recording: @recording,
          actor: @actor
        )
      end

      def deduplicate_access_recordings!(access_recordings)
        access_recordings.each do |access_recording|
          destroy_access_recording!(access_recording, manager_actor: manager_actor)
        end
      end
    end
  end
end
