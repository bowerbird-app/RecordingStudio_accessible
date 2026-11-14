# frozen_string_literal: true

module RecordingStudioAccessible
  # Distinct root ids for one actor's kept access grants.
  #
  # Independent grants stay. A dependent grant stays only when every manager
  # hop matches DependentAccess.effective?: a kept Access recording on the
  # same root, with a ranked role at least as strong, and no cycle.
  module EffectiveRootIds
    class << self
      def relation_for(access_recordings)
        sql = distinct_root_ids_sql(access_recordings)
        RecordingStudio::Recording.unscoped
                                  .from(Arel.sql("(#{sql}) AS effective_root_ids"))
                                  .reselect("effective_root_ids.root_recording_id")
      end

      private

      def distinct_root_ids_sql(access_recordings)
        <<~SQL.squish
          WITH RECURSIVE grant_walk AS (
            #{seed_sql(access_recordings)}
            UNION ALL
            #{step_sql}
          )
          #{finished_sql}
        SQL
      end

      def seed_sql(access_recordings)
        <<~SQL.squish
          #{seed_select_sql}
          FROM (#{seed_recordings_sql(access_recordings)}) seed
          LEFT JOIN #{accesses_table} accesses ON accesses.id = seed.recordable_id
        SQL
      end

      def step_sql
        <<~SQL.squish
          #{step_select_sql}
          FROM grant_walk
          INNER JOIN #{recordings_table} manager ON manager.id = grant_walk.manager_id
          INNER JOIN #{accesses_table} manager_access ON manager_access.id = manager.recordable_id
          WHERE #{step_filters_sql}
        SQL
      end

      def finished_sql
        <<~SQL.squish
          SELECT DISTINCT grant_walk.root_recording_id
          FROM grant_walk
          WHERE grant_walk.done AND grant_walk.root_recording_id IS NOT NULL
        SQL
      end

      def seed_select_sql
        <<~SQL.squish
          SELECT seed.root_recording_id AS root_recording_id,
                 COALESCE(seed.root_recording_id, seed.id) AS node_root_id,
                 accesses.depends_on_recording_id AS manager_id,
                 accesses.role AS node_role,
                 #{id_array('seed.id')} AS seen,
                 (accesses.id IS NULL OR accesses.depends_on_recording_id IS NULL) AS done
        SQL
      end

      def step_select_sql
        <<~SQL.squish
          SELECT grant_walk.root_recording_id,
                 COALESCE(manager.root_recording_id, manager.id),
                 manager_access.depends_on_recording_id,
                 manager_access.role,
                 grant_walk.seen || manager.id,
                 (manager_access.depends_on_recording_id IS NULL)
        SQL
      end

      def step_filters_sql
        [
          "NOT grant_walk.done",
          "manager.recordable_type = #{connection.quote('RecordingStudio::Access')}",
          RecordingStudio.kept_sql("manager"),
          "NOT (manager.id = ANY(grant_walk.seen))",
          "COALESCE(manager.root_recording_id, manager.id) = grant_walk.node_root_id",
          "#{role_rank_sql('manager_access.role')} >= #{role_rank_sql('grant_walk.node_role')}"
        ].join(" AND ")
      end

      def seed_recordings_sql(access_recordings)
        connection.unprepared_statement { access_recordings.to_sql }
      end

      def role_rank_sql(expression)
        branches = RecordingStudio::AccessRoles::ORDER.map do |name, rank|
          "WHEN #{connection.quote(name)} THEN #{Integer(rank)}"
        end
        "CASE #{expression} #{branches.join(' ')} END"
      end

      def id_array(expression)
        type = RecordingStudio::Recording.columns_hash.fetch("id").sql_type
        raise ArgumentError, "unsupported id type" unless type.match?(/\A[a-z_]+\z/)

        "ARRAY[#{expression}]::#{type}[]"
      end

      def recordings_table
        quote_table(RecordingStudio::Recording.table_name)
      end

      def accesses_table
        quote_table(RecordingStudio::Access.table_name)
      end

      def quote_table(name)
        connection.quote_table_name(name)
      end

      def connection
        RecordingStudio::Recording.connection
      end
    end
  end
end
