# frozen_string_literal: true

require "recording_studio_accessible/extracted/recording_studio/services/access_grant_lookup"
require "recording_studio_accessible/extracted/recording_studio/services/access_path"

module RecordingStudio
  module Services
    class AccessResolver
      def initialize(actor:, recording:)
        @actor = actor
        @recording = recording
      end

      def resolve_role
        return nil unless actor && recording

        path.lookup_recordings
            .filter_map { |path_recording| lookup.role_for(path_recording) }
            .select { |role| RecordingStudio::AccessRoles.value_for(role) }
            .max_by { |role| RecordingStudio::AccessRoles.value_for(role) }
      end

      private

      attr_reader :actor, :recording

      def path
        @path ||= AccessPath.new(recording: recording).build
      end

      def lookup
        @lookup ||= AccessGrantLookup.new(actor: actor, recordings: path.lookup_recordings)
      end
    end
  end
end
