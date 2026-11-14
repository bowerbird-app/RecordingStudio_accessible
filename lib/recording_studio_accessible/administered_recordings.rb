# frozen_string_literal: true

require "recording_studio_accessible/actor_type"
require "recording_studio_accessible/dependent_access"
require "recording_studio_accessible/extracted/recording_studio/access_roles"

module RecordingStudioAccessible
  # Parents among a candidate set where the actor's effective role is admin.
  #
  # Matches AccessPath: the recording, ancestors walked through
  # parent_recording_id (including trashed rows), and the root row when it
  # exists. A grant counts only when it is kept, ranked admin, and
  # DependentAccess.effective?.
  module AdministeredRecordings
    ACCESS_JOIN_SQL = <<~SQL.squish.freeze
      INNER JOIN recording_studio_accesses
        ON recording_studio_accesses.id = recording_studio_recordings.recordable_id
    SQL
    REACH_SQL = <<~SQL.squish.freeze
      WITH RECURSIVE chain AS (
        SELECT id AS candidate_id, id AS node_id, parent_recording_id, ARRAY[id] AS seen
        FROM %<table>s
        WHERE id IN (?)
        UNION ALL
        SELECT chain.candidate_id, parent.id, parent.parent_recording_id, chain.seen || parent.id
        FROM chain
        INNER JOIN %<table>s parent ON parent.id = chain.parent_recording_id
        WHERE NOT parent.id = ANY (chain.seen)
      )
      SELECT chain.candidate_id FROM chain WHERE chain.node_id IN (?)
      UNION
      SELECT candidates.id
      FROM %<table>s candidates
      INNER JOIN %<table>s roots ON roots.id = candidates.root_recording_id
      WHERE candidates.id IN (?) AND roots.id IN (?)
    SQL

    class << self
      def ids(candidate_ids:, actor:)
        candidates = Array(candidate_ids).compact.uniq
        return [] if candidates.empty? || actor.blank?

        granting = granting_node_ids(actor)
        return [] if granting.empty?

        reachable(candidates, granting)
      end

      private

      def granting_node_ids(actor)
        actor_grants(actor).filter_map do |grant|
          grant.parent_recording_id if admin_grant?(grant) && DependentAccess.effective?(grant)
        end.uniq
      end

      def admin_grant?(grant)
        RecordingStudio::AccessRoles.satisfies?(role: grant.recordable&.role, minimum_role: :admin)
      end

      def actor_grants(actor)
        kept_recordings
          .where(recordable_type: "RecordingStudio::Access")
          .joins(ACCESS_JOIN_SQL)
          .where(recording_studio_accesses: { actor_type: ActorType.for(actor), actor_id: actor.id })
          .includes(:recordable)
      end

      def kept_recordings
        RecordingStudio::Recording.unscoped.kept
      end

      def reachable(candidate_ids, granting_ids)
        sql = format(REACH_SQL, table: RecordingStudio::Recording.quoted_table_name)
        statement = RecordingStudio::Recording.sanitize_sql_array(
          [sql, candidate_ids, granting_ids, candidate_ids, granting_ids]
        )
        RecordingStudio::Recording.connection.select_values(statement)
      end
    end
  end
end
