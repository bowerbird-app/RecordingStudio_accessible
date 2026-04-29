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
          .where(recording_studio_accesses: actor_filter(actor))
          .order(created_at: :desc, id: :desc)
      end

      def access_recordings_for_actor_in(recordings:, actor:)
        return RecordingStudio::Recording.none unless actor

        recording_ids = Array(recordings).filter_map(&:id)
        return RecordingStudio::Recording.none if recording_ids.empty?

        RecordingStudio::Recording.unscoped
                                  .where(parent_recording_id: recording_ids,
                                         recordable_type: "RecordingStudio::Access",
                                         trashed_at: nil)
                                  .joins(ACCESS_JOIN_SQL)
                                  .where(recording_studio_accesses: actor_filter(actor))
                                  .order(created_at: :desc, id: :desc)
      end

      private

      def actor_filter(actor)
        { actor_type: stored_actor_type_for(actor), actor_id: actor.id }
      end

      def stored_actor_type_for(actor)
        base_class = actor.class.base_class
        return base_class.polymorphic_name if base_class.respond_to?(:polymorphic_name)

        base_class.name
      end
    end
  end
end
