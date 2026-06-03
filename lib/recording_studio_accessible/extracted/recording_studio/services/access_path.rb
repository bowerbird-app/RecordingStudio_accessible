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
        current = recording
        seen_ids = Set.new

        while current
          break if current.id && seen_ids.include?(current.id)

          seen_ids.add(current.id) if current.id
          @path_recordings << current
          current = current.parent_recording
        end

        self
      end

      def lookup_recordings
        (path_recordings + [root_recording]).compact.uniq
      end
    end
  end
end
