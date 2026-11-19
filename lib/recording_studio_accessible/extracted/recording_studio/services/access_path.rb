# frozen_string_literal: true

require "recording_studio_accessible/extracted/recording_studio/services/ancestor_records"

module RecordingStudio
  module Services
    class AccessPath
      # Request-scoped via the query cache. A write clears it with the SQL
      # cache, and a request ends by disabling that cache. Nothing is stored
      # on the process.
      PARENT_ANCESTOR_CACHE = :recording_studio_accessible_parent_ancestors

      attr_reader :recording, :path_recordings

      def initialize(recording:)
        @recording = recording
        @path_recordings = []
        @root_recording = nil
      end

      def build
        @path_recordings = ancestor_path
        self
      end

      def root_recording
        @root_recording ||= resolve_root_recording
      end

      def lookup_recordings
        (path_recordings + [root_recording]).compact.uniq
      end

      private

      # path_recordings stays this recording, then the nearest parent, up to
      # the top. A recording that is not persisted, or a walk that hits a
      # cycle or the depth cap, follows parent_recording.
      def ancestor_path
        return in_memory_path unless saved_with_ancestors?

        [recording, *parent_ancestors]
      rescue RecordingStudio::TreeWalkError
        in_memory_path
      end

      def saved_with_ancestors?
        recording.respond_to?(:ancestors) && recording.persisted?
      end

      def parent_ancestors
        parent_id = recording.parent_recording_id
        return [] if parent_id.blank?

        cache = ancestor_cache
        return AncestorRecords.load(parent_id) unless cache.respond_to?(:compute_if_absent)

        cache.compute_if_absent([PARENT_ANCESTOR_CACHE, parent_id]) do
          AncestorRecords.load(parent_id)
        end
      end

      def ancestor_cache
        # Store#compute_if_absent verified on Rails 8.1.4.1 (present since 8.1.0; gemspec ~> 8.1.0).
        ActiveRecord::Base.connection_pool.query_cache
      end

      def resolve_root_recording
        root_id = root_id_for(recording)
        return RecordingStudio.root_recording_or_self(recording) if root_id.blank?

        recording_on_path(root_id) || root_fallback(root_id)
      end

      def root_id_for(record)
        return unless record.respond_to?(:root_recording_id)

        record.root_recording_id.presence
      end

      def recording_on_path(root_id)
        path_recordings.find { |row| row.id.to_s == root_id.to_s }
      end

      def root_fallback(root_id)
        return recording if root_id.to_s == recording.id.to_s

        RecordingStudio.root_recording_or_self(recording)
      end

      def in_memory_path
        current = recording
        seen_ids = Set.new
        chain = []

        while current
          break if current.id && seen_ids.include?(current.id)

          seen_ids.add(current.id) if current.id
          chain << current
          current = current.parent_recording
        end

        chain
      end
    end
  end
end
