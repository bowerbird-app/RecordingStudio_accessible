# frozen_string_literal: true

module RecordingStudio
  module Services
    class AccessPath
      attr_reader :recording, :path_recordings, :boundary_parent, :root_recording

      def initialize(recording:)
        @recording = recording
        @path_recordings = []
        @boundary_parent = nil
        @root_recording = recording&.root_recording || recording
      end

      def build
        current = recording

        while current
          boundary_here = boundary_parent?(current)
          @path_recordings << current unless boundary_here && current.parent_recording_id.nil?
          @boundary_parent = current if boundary_here
          break if boundary_here

          current = current.parent_recording
        end

        self
      end

      def ancestors_above_boundary
        return [] unless boundary_parent

        ancestors = []
        current = boundary_parent.parent_recording

        while current
          ancestors << current
          break if boundary_parent?(current)

          current = current.parent_recording
        end

        ancestors
      end

      def lookup_recordings
        (path_recordings + ancestors_above_boundary + [root_recording]).compact.uniq
      end

      def boundary_recordable
        return unless boundary_parent

        RecordingStudio::Recording.unscoped
                                  .where(parent_recording_id: boundary_parent.id,
                                         recordable_type: "RecordingStudio::AccessBoundary",
                                         trashed_at: nil)
                                  .order(created_at: :desc, id: :desc)
                                  .first&.recordable
      end

      private

      def boundary_parent_ids
        @boundary_parent_ids ||= load_boundary_parent_ids
      end

      def load_boundary_parent_ids
        return Set.new unless root_recording

        RecordingStudio::Recording.unscoped
                                  .where(root_recording_id: boundary_root_id,
                                         recordable_type: "RecordingStudio::AccessBoundary",
                                         trashed_at: nil)
                                  .pluck(:parent_recording_id)
                                  .to_set
      end

      def boundary_root_id
        recording.root_recording_id || recording.id
      end

      def boundary_parent?(candidate)
        boundary_parent_ids.include?(candidate.id)
      end
    end
  end
end
