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
          access_recording = target_access_recording(existing_recordings)
          refuse_if_hook_rejects!(access_recording)

          if access_recording
            update_existing_access_recording(access_recording, existing_recordings)
          else
            create_access_recording
          end
        end
      end

      def target_access_recording(existing_recordings)
        return @access_recording if instance_variable_defined?(:@access_recording) && @access_recording

        existing_recordings.first
      end

      def refuse_if_hook_rejects!(existing_recording)
        recordable = existing_recording.recordable if existing_recording.respond_to?(:recordable)
        previous_role = recordable.role if recordable.respond_to?(:role)
        return if previous_role.present? && previous_role.to_s == @role.to_s

        ::RecordingStudioAccessible::BeforeAccessGrant.call!(
          ::RecordingStudioAccessible::BeforeAccessGrant.context_for(
            actor: @actor,
            recording: @recording,
            role: @role,
            source: grant_write_source(previous_role),
            granted_by: manager_actor,
            previous_role: previous_role
          )
        )
      end

      def grant_write_source(previous_role)
        configured = grant_source
        return configured unless configured == :grant

        previous_role.present? ? :role_change : :grant
      end

      def grant_source
        source = instance_variable_defined?(:@grant_source) ? @grant_source : :grant
        ::RecordingStudioAccessible::GrantContext::SOURCES.include?(source) ? source : :grant
      end

      def update_existing_access_recording(access_recording, existing_recordings)
        extras = existing_recordings.reject { |recording| recording.id == access_recording.id }
        deduplicate_access_recordings!(extras)

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
