# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    # Records one deleted event per voided grant through RecordingStudio.record_events!.
    class DeletedAccessEvents
      def self.write!(access_recordings, actor:)
        new(access_recordings, actor).write!
      end

      def initialize(access_recordings, actor)
        @access_recordings = access_recordings
        @actor = actor
      end

      def write!
        return if @access_recordings.empty?

        preload
        plans = @access_recordings.map { |access_recording| plan_for(access_recording) }
        RecordingStudio.record_events!(plans.map { |plan| entry_for(plan) })
      end

      private

      def preload
        records = @access_recordings.grep(ActiveRecord::Base)
        return if records.empty?

        preload_associations(records, %i[parent_recording recordable])
        parents = records.filter_map(&:parent_recording).grep(ActiveRecord::Base)
        preload_associations(parents, [:recordable])
      end

      def preload_associations(records, associations)
        return if records.empty?

        ActiveRecord::Associations::Preloader.new(records: records, associations: associations).call
      end

      def plan_for(access_recording)
        target = access_recording.parent_recording || access_recording
        recordable = target.recordable
        recordable.save! unless recordable.persisted?

        {
          target: target,
          recordable: recordable,
          metadata: RecordingStudio::Metadata.normalize(metadata_for(access_recording)),
          actor: event_actor,
          impersonator: RecordingStudio.configuration.impersonator&.call
        }
      end

      def entry_for(plan)
        {
          action: "deleted",
          recording: plan[:target],
          recordable: plan[:recordable],
          actor: plan[:actor],
          impersonator: plan[:impersonator],
          metadata: plan[:metadata]
        }
      end

      def metadata_for(access_recording)
        { access_recording_id: access_recording.id, access_id: access_recording.recordable_id }
      end

      def event_actor
        RecordingStudio::Authorization.assert_actor!(@actor || RecordingStudio.configuration.actor&.call)
      end
    end
  end
end
