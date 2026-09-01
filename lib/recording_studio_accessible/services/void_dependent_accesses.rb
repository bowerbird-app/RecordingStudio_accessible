# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class VoidDependentAccesses < BaseService
      include AccessRecordLifecycle

      def initialize(manager_access_recording_id:, manager_actor: nil, moved: false)
        @manager_access_recording_id = manager_access_recording_id
        @manager_actor = manager_actor
        @moved = moved
      end

      private

      attr_reader :manager_actor

      def perform
        return success([]) if @manager_access_recording_id.blank?

        voided = []
        RecordingStudio::Recording.transaction do
          dependents.find_each do |access_recording|
            next unless should_void?(access_recording)

            destroy_access_recording!(access_recording, manager_actor: manager_actor)
            voided << access_recording.id
          end
        end

        success(voided)
      rescue StandardError => e
        failure(e)
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
