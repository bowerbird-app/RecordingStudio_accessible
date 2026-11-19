# frozen_string_literal: true

module RecordingStudioAccessible
  class SharedWith
    class Query
      CURSOR_SQL = "(recording_studio_recordings.created_at, recording_studio_recordings.id) < (?, ?)"
      ITEM_JOIN = <<~SQL.squish.freeze
        INNER JOIN recording_studio_recordings shared_with_items
          ON shared_with_items.id = recording_studio_recordings.parent_recording_id
      SQL
      ROOT_JOIN = <<~SQL.squish.freeze
        INNER JOIN recording_studio_recordings shared_with_roots
          ON shared_with_roots.id = recording_studio_recordings.parent_recording_id
      SQL
      ITEM_KEPT = "shared_with_items.parent_recording_id IS NOT NULL AND shared_with_items.trashed_at IS NULL"
      ROOT_PARENT = "shared_with_roots.parent_recording_id IS NULL"
      PRELOADS = [:recordable, { parent_recording: :recordable }, { root_recording: :recordable }].freeze

      def initialize(actor)
        @actor = actor
      end

      def window(point)
        scope = item_scope.order(created_at: :desc, id: :desc)
        scope = scope.where(CURSOR_SQL, point[0], point[1]) if point
        scope.preload(*PRELOADS).limit(SharedWith::BATCH).to_a
      end

      private

      attr_reader :actor

      def item_scope
        scope = actor_grants.joins(ITEM_JOIN).where(ITEM_KEPT)
        return scope if excluded_root_ids.empty?

        scope.where("shared_with_items.root_recording_id NOT IN (?)", excluded_root_ids)
      end

      def excluded_root_ids
        @excluded_root_ids ||= root_grants.select { |grant| DependentAccess.effective?(grant) }
                                          .map(&:parent_recording_id).uniq
      end

      def root_grants
        actor_grants.joins(ROOT_JOIN).where(ROOT_PARENT).preload(:recordable).to_a
      end

      def actor_grants
        ids = RecordingStudioAccessible.access_grants_for(actor: actor)
                                       .where("recording_studio_recordings.trashed_at IS NULL")
                                       .select(:id)
        RecordingStudio::Recording.unscoped.where(id: ids)
      end
    end
  end
end
