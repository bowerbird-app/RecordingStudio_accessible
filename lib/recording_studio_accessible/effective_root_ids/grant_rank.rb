# frozen_string_literal: true

module RecordingStudioAccessible
  module EffectiveRootIds
    # Per-type rank for a manager hop. With no custom role the comparison
    # stays the built-in CASE and does not join the grant's parent.
    module GrantRank
      private

      def role_rank_sql(expression, type_expression = nil)
        RoleRegistry.rank_sql(connection, expression, type_expression)
      end

      def custom_ranks?
        RoleRegistry.custom?
      end

      def node_type_select
        return "" unless custom_ranks?

        "seed_parent.recordable_type AS node_type,"
      end

      def step_node_type_select
        return "" unless custom_ranks?

        "manager_parent.recordable_type,"
      end

      def seed_parent_join
        return "" unless custom_ranks?

        "LEFT JOIN #{recordings_table} seed_parent ON seed_parent.id = seed.parent_recording_id"
      end

      def manager_parent_join
        return "" unless custom_ranks?

        "INNER JOIN #{recordings_table} manager_parent ON manager_parent.id = manager.parent_recording_id"
      end

      def manager_covers_sql
        if custom_ranks?
          "#{role_rank_sql('manager_access.role', 'manager_parent.recordable_type')} >= " \
            "#{role_rank_sql('grant_walk.node_role', 'grant_walk.node_type')}"
        else
          "#{role_rank_sql('manager_access.role')} >= #{role_rank_sql('grant_walk.node_role')}"
        end
      end
    end
  end
end
