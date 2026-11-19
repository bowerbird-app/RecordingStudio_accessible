# frozen_string_literal: true

module RecordingStudio
  module Services
    # Ancestor rows for one parent, nearest parent first, in a single query.
    # A cycle or a walk past the depth cap raises TreeWalkError.
    class AncestorRecords
      def self.load(parent_id)
        new(parent_id).load
      end

      def initialize(parent_id)
        @parent_id = parent_id
        @recordings = RecordingStudio::Recording
      end

      def load
        rows = @recordings.connection.select_all(sql)
        raise_walk_error!(rows)
        columns = @recordings.column_names
        rows.map { |row| @recordings.instantiate(attributes_for(row, columns)) }
      end

      private

      def attributes_for(row, columns)
        row.to_h.slice(*columns)
      end

      def raise_walk_error!(rows)
        failed = rows.find { |row| flagged?(row, "ancestor_cycle") || flagged?(row, "ancestor_depth_capped") }
        return unless failed

        raise RecordingStudio::TreeWalkError, walk_message(failed)
      end

      def walk_message(row)
        recording_id = row.fetch("id")
        return cycle_message(recording_id) if flagged?(row, "ancestor_cycle")

        depth_message(recording_id)
      end

      def cycle_message(recording_id)
        "Recording tree contains a cycle at recording #{recording_id}"
      end

      def depth_message(recording_id)
        cap = RecordingStudio::Tree::MAX_WALK_DEPTH
        "Recording tree walk exceeded the depth cap of #{cap} at recording #{recording_id}"
      end

      def flagged?(row, name)
        value = row[name]
        value == true || value.to_i == 1
      end

      def sql
        <<~SQL.squish
          WITH RECURSIVE ancestors AS (
            #{seed_sql}
            UNION ALL
            #{step_sql}
          )
          #{rows_sql}
        SQL
      end

      # Recording ids are uuid. Core's install migration and the dummy schema both use id: :uuid.
      def seed_sql
        <<~SQL.squish
          SELECT recording.id, recording.parent_recording_id, 0 AS depth,
                 ARRAY[recording.id]::uuid[] AS path, 0 AS cycle, 0 AS depth_capped
          FROM #{table} recording
          WHERE recording.id = #{quoted_parent_id}
        SQL
      end

      def step_sql
        <<~SQL.squish
          SELECT parent.id, parent.parent_recording_id, ancestors.depth + 1,
                 ancestors.path || parent.id,
                 CASE WHEN parent.id = ANY (ancestors.path) THEN 1 ELSE 0 END,
                 CASE WHEN ancestors.depth + 1 >= #{depth_cap} THEN 1 ELSE 0 END
          FROM ancestors
          INNER JOIN #{table} parent ON parent.id = ancestors.parent_recording_id
          WHERE ancestors.parent_recording_id IS NOT NULL
            AND ancestors.cycle = 0 AND ancestors.depth_capped = 0
        SQL
      end

      def rows_sql
        <<~SQL.squish
          SELECT #{table}.*, ancestors.cycle AS ancestor_cycle,
                 ancestors.depth_capped AS ancestor_depth_capped
          FROM #{table}
          INNER JOIN ancestors ON ancestors.id = #{table}.id
          ORDER BY ancestors.depth ASC
        SQL
      end

      def table
        @recordings.quoted_table_name
      end

      def quoted_parent_id
        @recordings.connection.quote(@parent_id)
      end

      def depth_cap
        RecordingStudio::Tree::MAX_WALK_DEPTH.to_i
      end
    end
  end
end
