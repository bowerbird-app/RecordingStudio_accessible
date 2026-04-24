# frozen_string_literal: true

module RecordingStudioAccessible
  module DirectAccessQuery
    ACCESS_JOIN_SQL = <<~SQL.squish.freeze
      INNER JOIN recording_studio_accesses
        ON recording_studio_accesses.id = recording_studio_recordings.recordable_id
    SQL

    class << self
      def access_recordings_for(recording)
        RecordingStudio::Recording.unscoped
                                  .where(parent_recording_id: recording.id)
                                  .where(recordable_type: "RecordingStudio::Access")
                                  .where(trashed_at: nil)
      end

      def access_recordings_for_actor(recording:, actor:)
        return RecordingStudio::Recording.none unless actor

        access_recordings_for(recording)
          .joins(ACCESS_JOIN_SQL)
          .where(recording_studio_accesses: { actor_type: actor.class.name, actor_id: actor.id })
          .order(created_at: :desc, id: :desc)
      end
    end
  end
end
