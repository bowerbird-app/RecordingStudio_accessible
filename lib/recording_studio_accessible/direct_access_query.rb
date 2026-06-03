# frozen_string_literal: true

module RecordingStudioAccessible
  module DirectAccessQuery
    ACCESS_JOIN_SQL = <<~SQL.squish.freeze
      INNER JOIN recording_studio_accesses
        ON recording_studio_accesses.id = recording_studio_recordings.recordable_id
    SQL

    class << self
      def access_recordings_for(recording)
        active_recordings_scope
          .where(parent_recording_id: recording.id)
          .where(recordable_type: "RecordingStudio::Access")
      end

      def access_recordings_for_actor(recording:, actor:)
        return RecordingStudio::Recording.none unless actor

        access_recordings_for(recording)
          .joins(ACCESS_JOIN_SQL)
          .where(recording_studio_accesses: actor_filter(actor))
          .order(created_at: :desc, id: :desc)
      end

      def access_recordings_for_actor_in(recordings:, actor:)
        return RecordingStudio::Recording.none unless actor

        recording_ids = Array(recordings).filter_map(&:id)
        return RecordingStudio::Recording.none if recording_ids.empty?

        active_recordings_scope
          .where(parent_recording_id: recording_ids, recordable_type: "RecordingStudio::Access")
          .joins(ACCESS_JOIN_SQL)
          .where(recording_studio_accesses: actor_filter(actor))
          .order(created_at: :desc, id: :desc)
      end

      private

      def active_recordings_scope
        scope = RecordingStudio::Recording.unscoped
        return scope unless RecordingStudio::Recording.column_names.include?("trashed_at")

        scope.where(trashed_at: nil)
      end

      def actor_filter(actor)
        { actor_type: RecordingStudioAccessible::ActorType.for(actor), actor_id: actor.id }
      end
    end
  end
end
