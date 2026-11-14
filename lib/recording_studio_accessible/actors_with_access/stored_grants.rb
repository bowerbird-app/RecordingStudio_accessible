# frozen_string_literal: true

module RecordingStudioAccessible
  # Grant rows and actor records for one lookup. Refresh drops the grant
  # memo and reads it again. Actors already loaded stay. The reread runs
  # with the query cache off so a write in the same transaction is visible.
  module ActorsWithAccess::StoredGrants
    def any_actor?(minimum_role: :view)
      return false unless recording

      roles_by_key.any? do |key, role|
        role_satisfies?(role, minimum_role) && actors_by_key[key]
      end
    end

    def refresh!
      clear_grant_memo!
      RecordingStudio::Recording.uncached { reload_grant_memo! }
      self
    end

    def ancestor_recordings
      recordings = path_recordings.drop(1)
      preload_recordables(recordings)
      recordings
    end

    def grants_for(parent)
      parent_id = parent.respond_to?(:id) ? parent.id : parent
      Array(grants_by_parent_id[parent_id]).sort_by { |grant| [grant.created_at, grant.id.to_s] }
    end

    def actor_for(access_recording)
      access = access_recording.respond_to?(:recordable) ? access_recording.recordable : nil
      return unless access

      actor_at(access.actor_type, access.actor_id)
    end

    private

    def clear_grant_memo!
      @grants = nil
      @effective_grants = nil
      @roles_by_key = nil
      @grants_by_parent_id = nil
      @path_recordings = nil
    end

    def reload_grant_memo!
      grants
      load_missing_actors!
      roles_by_key
    end

    def path_recordings
      grants
      Array(@path_recordings)
    end

    def grants_by_parent_id
      @grants_by_parent_id ||= grants.group_by(&:parent_recording_id)
    end

    def preload_recordables(recordings)
      pending = recordings.select do |item|
        item.respond_to?(:association) && !item.association(:recordable).loaded?
      end
      return if pending.empty?

      ActiveRecord::Associations::Preloader.new(records: pending, associations: :recordable).call
    end

    def load_missing_actors!
      @actors_by_key ||= {}
      missing = actor_keys.reject { |key| @actors_by_key.key?(key) }
      return if missing.empty?

      missing.group_by(&:first).each do |type, pairs|
        assign_actors(@actors_by_key, type, pairs)
      end
    end
  end
end
