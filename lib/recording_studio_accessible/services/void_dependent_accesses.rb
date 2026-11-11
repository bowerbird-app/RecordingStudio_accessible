# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class VoidDependentAccesses < BaseService
      include AccessRecordLifecycle

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

        voided = []
        RecordingStudio::Recording.transaction do
          to_void = []
          dependents.find_each do |access_recording|
            to_void << access_recording if should_void?(access_recording)
          end

          LastAdminGuard.protect!(
            recordings: parent_recordings_for(to_void),
            allow_last_admin_removal: @allow_last_admin_removal
          ) do
            to_void.each do |access_recording|
              destroy_access_recording!(access_recording, manager_actor: manager_actor)
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

      def parent_recordings_for(access_recordings)
        access_recordings.filter_map do |access_recording|
          access_recording.parent_recording if access_recording.respond_to?(:parent_recording)
        end
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
