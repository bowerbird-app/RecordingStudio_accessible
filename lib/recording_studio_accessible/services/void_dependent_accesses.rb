# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class VoidDependentAccesses < BaseService
      include AccessRecordLifecycle

      VOID_BATCH = 100

      def initialize(manager_access_recording_id:, manager_actor: nil, moved: false,
                     allow_last_admin_removal: false)
        @manager_access_recording_id = manager_access_recording_id
        @manager_actor = manager_actor
        @moved = moved
        @allow_last_admin_removal = allow_last_admin_removal
      end

      private

      attr_reader :manager_actor

      def perform
        return success([]) if @manager_access_recording_id.blank?

        to_void = []
        dependents.find_each(batch_size: VOID_BATCH) do |access_recording|
          to_void << access_recording if should_void?(access_recording)
        end

        voided = []
        RecordingStudio::Recording.transaction do
          next if to_void.empty?

          LastAdminGuard.protect!(
            recordings: parent_recordings_for(to_void),
            allow_last_admin_removal: @allow_last_admin_removal
          ) do
            write_deleted_events!(to_void)
            to_void.each do |access_recording|
              destroy_access_recording!(access_recording, manager_actor: manager_actor, record_event: false)
              voided << access_recording.id
            end
          end
        end

        success(voided)
      rescue ::RecordingStudioAccessible::LastAdminError => e
        failure(e, errors: [e])
      rescue StandardError => e
        unexpected_failure(e)
      end

      # One deleted event per grant, in void order, with the same payload as
      # destroy_access_recording!. The insert is one statement.
      def write_deleted_events!(access_recordings)
        DeletedAccessEvents.write!(access_recordings, actor: manager_actor)
      end

      def parent_recordings_for(access_recordings)
        access_recordings.filter_map do |access_recording|
          next unless access_recording.respond_to?(:parent_recording)

          access_recording.parent_recording
        end.uniq
      end

      def dependents
        RecordingStudioAccessible::DirectAccessQuery.access_recordings_depending_on(@manager_access_recording_id)
      end

      def should_void?(access_recording)
        return true if moved?

        !RecordingStudioAccessible::DependentAccess.effective?(access_recording)
      end

      def moved?
        @moved == true
      end

      def service_args
        {
          manager_access_recording_id: @manager_access_recording_id,
          manager_actor_gid: global_id_string_for(manager_actor),
          moved: moved?
        }
      end
    end
  end
end
