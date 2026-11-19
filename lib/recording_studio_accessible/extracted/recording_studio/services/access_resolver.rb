# frozen_string_literal: true

require "recording_studio_accessible/extracted/recording_studio/services/access_grant_lookup"
require "recording_studio_accessible/extracted/recording_studio/services/access_path"

module RecordingStudio
  module Services
    class AccessResolver
      def initialize(actor:, recording:, path: nil, lookup: nil)
        @actor = actor
        @recording = recording
        @path = path
        @lookup = lookup
      end

      def resolve_role
        return nil unless actor && recording

        best_name = nil
        best_rank = nil
        path.lookup_recordings.each do |node|
          lookup.roles_for(node).each do |role|
            best_name, best_rank = stronger_role(best_name, best_rank, node, role)
          end
        end
        best_name
      end

      def stronger_role(best_name, best_rank, node, role)
        rank = RecordingStudioAccessible::RoleRegistry.rank_on(node, role)
        return [best_name, best_rank] unless rank
        return [best_name, best_rank] if best_rank && rank <= best_rank

        [role, rank]
      end

      def meets?(minimum_role)
        return false unless actor && recording
        return false if closed_custom_role?(recording, minimum_role)

        path.lookup_recordings.any? do |node|
          lookup.roles_for(node).any? do |role|
            RecordingStudioAccessible::RoleRegistry.meets?(node, role, minimum_role)
          end
        end
      end

      def any_effective_grant?
        return false unless actor && recording

        roles_on_path.any?
      end

      def any_role?(roles)
        return false unless actor && recording

        wanted = normalized_role_names(roles)
        return false if wanted.empty?

        path.lookup_recordings.any? do |path_recording|
          lookup.roles_for(path_recording).intersect?(wanted)
        end
      end

      def closed_custom_role?(node, role)
        RecordingStudioAccessible::RoleRegistry.custom_name?(role) &&
          !RecordingStudioAccessible::RoleRegistry.declares?(node, role)
      end

      def normalized_role_names(roles)
        Array(roles).filter_map { |role| RecordingStudio::AccessRoles.normalize(role)&.strip&.presence }
      end

      private

      attr_reader :actor, :recording

      def roles_on_path
        path.lookup_recordings.flat_map { |path_recording| lookup.roles_for(path_recording) }
      end

      def path
        @path ||= AccessPath.new(recording: recording).build
      end

      def lookup
        @lookup ||= AccessGrantLookup.new(actor: actor, recordings: path.lookup_recordings)
      end
    end
  end
end
