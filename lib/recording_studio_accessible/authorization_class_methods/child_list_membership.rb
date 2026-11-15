# frozen_string_literal: true

module RecordingStudioAccessible
  module AuthorizationClassMethods
    # AccessPath adds a child's root when that root is not on the parent path.
    # A grant on that root can admit the child. It cannot remove one, because
    # the strongest role on the path wins.
    class ChildListMembership
      def initialize(candidates, request)
        @candidates = candidates
        @request = request
      end

      # Enough of AccessResolver for ChildListFloor. Roles are already the
      # effective ones from AccessGrantLookup.
      class GrantDecision
        def initialize(roles)
          @roles = roles
        end

        def resolve_role
          RecordingStudio::AccessRoles.strongest(@roles)
        end

        def any_effective_grant?
          @roles.any?
        end
      end

      IdRef = Struct.new(:id)

      def ids
        return @candidates.pluck(:id) if parent_meets_floor?

        (direct_child_ids + off_path_child_ids).uniq
      end

      private

      def parent_meets_floor?
        @request.floor.keep?(parent_resolver)
      end

      def parent_resolver
        @parent_resolver ||= RecordingStudio::Services::AccessResolver.new(
          actor: @request.actor,
          recording: @request.parent_recording,
          path: parent_path
        )
      end

      def parent_path
        @parent_path ||= RecordingStudio::Services::AccessPath.new(
          recording: @request.parent_recording
        ).build
      end

      def parent_lookup_ids
        parent_path.lookup_recordings.filter_map(&:id)
      end

      def direct_child_ids
        ids_meeting_floor(grants_on(@candidates))
      end

      def off_path_child_ids
        root_ids = off_path_scope.distinct.pluck(:root_recording_id).compact
        return [] if root_ids.empty?

        meeting = ids_meeting_floor(grants_for(root_ids))
        return [] if meeting.empty?

        off_path_scope.where(root_recording_id: meeting).pluck(:id)
      end

      def off_path_scope
        @candidates.where.not(root_recording_id: parent_lookup_ids)
      end

      def grants_for(recording_ids)
        grants_on(recording_ids.map { |recording_id| IdRef.new(recording_id) })
      end

      def grants_on(recordings)
        DirectAccessQuery.access_recordings_for_actor_in(
          recordings: recordings,
          actor: @request.actor
        ).preload(:recordable).to_a
      end

      def ids_meeting_floor(grants)
        return [] if grants.empty?

        lookup = RecordingStudio::Services::AccessGrantLookup.new(
          actor: @request.actor,
          recordings: [],
          access_recordings: grants
        )
        grants.map(&:parent_recording_id).uniq.select do |recording_id|
          @request.floor.keep?(GrantDecision.new(lookup.roles_for(IdRef.new(recording_id))))
        end
      end
    end
    private_constant :ChildListMembership
  end
end
