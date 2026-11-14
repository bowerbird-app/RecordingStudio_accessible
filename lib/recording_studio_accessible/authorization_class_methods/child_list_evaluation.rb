# frozen_string_literal: true

module RecordingStudioAccessible
  module AuthorizationClassMethods
    # One pass over the kept direct children.
    #
    # Ancestor grants load once. Child grants load once. Audience rules and
    # constraints load once. Each child still runs AccessResolver's role
    # precedence on its own path, including a root that sits off that path.
    class ChildListEvaluation
      def initialize(children, request)
        @children = children
        @request = request
        @paths = children.map { |child| RecordingStudio::Services::AccessPath.new(recording: child).build }
      end

      def allowed_ids
        lookup = grant_lookup
        snapshot = AudienceSnapshot.load(@children)
        actions = RecordingStudioAccessible.configuration.action_audiences.keys

        @children.each_with_index.filter_map do |child, index|
          resolve_audiences(child, actions, snapshot)
          child.id if @request.floor.keep?(resolver_for(child, index, lookup))
        end
      end

      private

      # Same audience precedence as a single-recording lookup. The result is
      # not a grant and does not add or remove a child.
      def resolve_audiences(child, actions, snapshot)
        actions.each do |action|
          AudienceResolver.effective_audience(recording: child, action: action, snapshot: snapshot)
        end
      end

      def resolver_for(child, index, lookup)
        RecordingStudio::Services::AccessResolver.new(
          actor: @request.actor,
          recording: child,
          path: @paths[index],
          lookup: lookup
        )
      end

      def grant_lookup
        RecordingStudio::Services::AccessGrantLookup.new(
          actor: @request.actor,
          recordings: lookup_recordings,
          access_recordings: ancestor_grants + child_grants
        )
      end

      def lookup_recordings
        @lookup_recordings ||= @paths.flat_map(&:lookup_recordings).uniq
      end

      def ancestor_grants
        load_grants(ancestor_recordings)
      end

      def child_grants
        load_grants(@children)
      end

      def ancestor_recordings
        child_ids = @children.to_h { |child| [child.id, true] }
        lookup_recordings.reject { |recording| child_ids[recording.id] }
      end

      def load_grants(recordings)
        return [] if recordings.empty?

        DirectAccessQuery.access_recordings_for_actor_in(
          recordings: recordings,
          actor: @request.actor
        ).preload(:recordable).to_a
      end
    end
    private_constant :ChildListEvaluation
  end
end
