# frozen_string_literal: true

module RecordingStudio
  module Services
    class AccessPath
      attr_reader :recording, :path_recordings, :root_recording

      def initialize(recording:)
        @recording = recording
        @path_recordings = []
        @root_recording = RecordingStudio.root_recording_or_self(recording)
      end

      def build
        @path_recordings = ancestor_path
        self
      end

      def lookup_recordings
        (path_recordings + [root_recording]).compact.uniq
      end

      private

      # ancestors is root-first. path_recordings stays this recording, then the
      # nearest parent, up to the top. A recording that is not persisted, or a
      # walk that hits a cycle or the depth cap, follows parent_recording.
      def ancestor_path
        return in_memory_path unless saved_with_ancestors?

        [recording, *recording.ancestors.reverse]
      rescue RecordingStudio::TreeWalkError
        in_memory_path
      end

      def saved_with_ancestors?
        recording.respond_to?(:ancestors) && recording.persisted?
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
