# frozen_string_literal: true

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
      seen = build_actor_keys(direct_access_recordings)
      ancestor_access_recordings.filter_map do |access_recording|
        inherited_row_if_new(access_recording, seen)
      end
    end

    def inherited_row_if_new(access_recording, seen)
      actor = access_recording.recordable.actor
      return unless actor

      key = actor_key_for(actor)
      return if seen.include?(key)

      row = row_for(access_recording, inherited: true)
      return unless row&.effective_role

      seen << key
      row
    end

    def row_for(access_recording, inherited:)
      actor = access_recording.recordable.actor
      return unless actor

      Row.new(
        inherited: inherited,
        role: access_recording.recordable.role,
        effective_role: effective_role_for(actor),
        actor: actor,
        source_recording: inherited ? access_recording.parent_recording : @recording,
        access_recording: inherited ? nil : access_recording
      )
    end

    def direct_access_recordings
      @direct_access_recordings ||= DirectAccessQuery.access_recordings_for(@recording)
                                                     .order(created_at: :asc, id: :asc)
    end

    def ancestor_access_recordings
      ancestor_recordings.flat_map do |recording|
        DirectAccessQuery.access_recordings_for(recording).order(created_at: :asc, id: :asc)
      end
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

    def build_actor_keys(access_recordings)
      access_recordings.filter_map do |access_recording|
        actor = access_recording.recordable.actor
        actor_key_for(actor) if actor
      end.to_set
    end

    def actor_key_for(actor)
      [ActorType.for(actor), actor.id]
    end

    def effective_role_for(actor)
      RecordingStudioAccessible.role_for(actor: actor, recording: @recording)
    end
  end
end
