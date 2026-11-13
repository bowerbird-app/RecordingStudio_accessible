# frozen_string_literal: true

require "recording_studio_accessible/actors_with_access"

module RecordingStudioAccessible
  class AccessGrantList
    Row = Struct.new(
      :inherited,
      :role,
      :effective_role,
      :actor,
      :source_recording,
      :access_recording,
      keyword_init: true
    )

    def self.rows_for(recording)
      new(recording).rows
    end

    def initialize(recording)
      @recording = recording
    end

    def rows
      direct_rows + inherited_rows
    end

    def direct_row_for(actor)
      return unless actor

      key = actor_key_for(actor)
      direct_rows.find { |row| actor_key_for(row.actor) == key }
    end

    def inherited_row_for(actor)
      return unless actor

      key = actor_key_for(actor)
      inherited_rows.find { |row| actor_key_for(row.actor) == key }
    end

    private

    def direct_rows
      @direct_rows ||= direct_access_recordings.filter_map do |access_recording|
        row_for(access_recording, inherited: false)
      end
    end

    def inherited_rows
      @inherited_rows ||= collect_inherited_rows
    end

    def collect_inherited_rows
      seen = direct_rows.to_set { |row| actor_key_for(row.actor) }
      ancestor_access_recordings.filter_map do |access_recording|
        inherited_row_if_new(access_recording, seen)
      end
    end

    def inherited_row_if_new(access_recording, seen)
      actor = actor_for(access_recording)
      return unless actor

      key = actor_key_for(actor)
      return if seen.include?(key)

      row = row_for(access_recording, inherited: true)
      return unless row&.effective_role

      seen << key
      row
    end

    def row_for(access_recording, inherited:)
      actor = actor_for(access_recording)
      return unless actor && lookup.effective_grant?(access_recording)

      Row.new(inherited: inherited, role: access_recording.recordable.role, actor: actor,
              effective_role: effective_role_for(actor),
              source_recording: inherited ? access_recording.parent_recording : @recording,
              access_recording: inherited ? nil : access_recording)
    end

    def direct_access_recordings
      @direct_access_recordings ||= ordered_grants_for(@recording)
    end

    def ancestor_access_recordings
      ancestor_recordings.flat_map { |recording| ordered_grants_for(recording) }
    end

    def ordered_grants_for(recording)
      Array(grants_by_parent_id[recording&.id]).sort_by { |grant| [grant.created_at, grant.id.to_s] }
    end

    def grants_by_parent_id
      @grants_by_parent_id ||= lookup.grants.group_by(&:parent_recording_id)
    end

    def ancestor_recordings
      ancestors = []
      current_recording = @recording.parent_recording

      while current_recording
        ancestors << current_recording
        current_recording = current_recording.parent_recording
      end

      ancestors
    end

    def actor_for(access_recording)
      access = access_recording.recordable
      return unless access

      lookup.actor_at(access.actor_type, access.actor_id)
    end

    def actor_key_for(actor)
      [ActorType.for(actor), actor.id]
    end

    def effective_role_for(actor)
      lookup.effective_role_for(actor)
    end

    def lookup
      @lookup ||= ActorsWithAccess.new(@recording)
    end
  end
end
