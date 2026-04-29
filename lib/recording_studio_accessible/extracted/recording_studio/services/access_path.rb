# frozen_string_literal: true

module RecordingStudio
  module Services
    class AccessPath
      attr_reader :recording, :path_recordings, :root_recording

      def initialize(recording:)
        @recording = recording
        @path_recordings = []
        @root_recording = recording&.root_recording || recording
      end

      def build
        current = recording

        while current
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
