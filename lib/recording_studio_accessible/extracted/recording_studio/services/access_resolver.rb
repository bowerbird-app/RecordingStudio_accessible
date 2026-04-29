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

        direct_role = direct_role_on_path
        return direct_role if direct_role

        lookup.role_for(path.root_recording)
      end

      private

      attr_reader :actor, :recording

      def path
        @path ||= AccessPath.new(recording: recording).build
      end

      def lookup
        @lookup ||= AccessGrantLookup.new(actor: actor, recordings: path.lookup_recordings)
      end

      def direct_role_on_path
        path.path_recordings.filter_map { |path_recording| lookup.role_for(path_recording) }.first
      end
    end
  end
end
