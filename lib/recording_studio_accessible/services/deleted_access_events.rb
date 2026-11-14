# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    # Records one deleted event per voided grant, then inserts the batch.
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
        lock!(plans)
        plans.each { |plan| authorize!(plan) }
        DeletedAccessEventInsert.insert!(plans)
      end

      private

      def preload
        records = @access_recordings.grep(ActiveRecord::Base)
        return if records.empty?

        preload_associations(records, %i[parent_recording recordable])
        parents = records.filter_map(&:parent_recording).grep(ActiveRecord::Base)
        preload_associations(parents, %i[recordable root_recording])
      end

      def preload_associations(records, associations)
        return if records.empty?

        ActiveRecord::Associations::Preloader.new(records: records, associations: associations).call
      end

      def plan_for(access_recording)
        target = access_recording.parent_recording || access_recording
        root = RecordingStudio.root_recording_or_self(target)
        recordable = target.recordable
        recordable.save! unless recordable.persisted?

        {
          target: target,
          root: root,
          recordable: recordable,
          metadata: RecordingStudio::Metadata.normalize(metadata_for(access_recording)),
          actor: event_actor,
          impersonator: RecordingStudio.configuration.impersonator&.call
        }
      end

      def metadata_for(access_recording)
        { access_recording_id: access_recording.id, access_id: access_recording.recordable_id }
      end

      def event_actor
        RecordingStudio::Authorization.assert_actor!(@actor || RecordingStudio.configuration.actor&.call)
      end

      def lock!(plans)
        locked_ids = {}
        plans.each do |plan|
          lock_once!(plan[:target], locked_ids)
          lock_once!(plan[:root], locked_ids)
          RecordingStudio.assert_root_recording!(plan[:root])
          RecordingStudio.assert_recording_belongs_to_root!(
            plan[:root], plan[:target], message: "recording must belong to the provided root_recording"
          )
        end
      end

      def lock_once!(recording, locked_ids)
        return if recording.nil? || locked_ids[recording.id]

        RecordingStudio::Recording.unscoped.lock.find(recording.id)
        locked_ids[recording.id] = true
      end

      def authorize!(plan)
        context = {
          action: "deleted",
          recordable: plan[:recordable],
          recording: plan[:target],
          root_recording: plan[:root],
          parent_recording: nil,
          actor: plan[:actor],
          impersonator: plan[:impersonator],
          metadata: plan[:metadata]
        }
        RecordingStudio::Authorization.authorize_write!(**context)
        RecordingStudio::Hooks.run(:before_record, **context)
      end
    end
  end
end
