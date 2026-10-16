# frozen_string_literal: true

module RecordingStudioAccessible
  module AccessRequestReviewers
    class << self
      def for(recording)
        return [] if recording.blank?

        ancestor_chain(recording).flat_map { |node| admin_actors_on(node) }
                                 .compact
                                 .uniq { |actor| [ActorType.for(actor), actor.id] }
      end

      private

      def ancestor_chain(recording)
        nodes = []
        current = recording
        while current
          nodes << current
          break if current.parent_recording_id.blank?

          current = current.parent_recording
        end
        nodes
      end

      def admin_actors_on(recording)
        DirectAccessQuery.access_recordings_for(recording)
                         .joins(DirectAccessQuery::ACCESS_JOIN_SQL)
                         .where(recording_studio_accesses: { role: "admin" })
                         .filter_map { |access_recording| access_recording.recordable&.actor }
      end
    end
  end
end
