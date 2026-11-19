# frozen_string_literal: true

module RecordingStudioAccessible
  module AuthorizationClassMethods
    # A grant counts toward a floor only when its own recording's type ranks it there.
    module RankedGrantSql
      private

      def ranked_on_parent_sql(minimum_role)
        connection = RecordingStudio::Access.connection
        "EXISTS (#{parent_rank_select(connection, minimum_role)})"
      end

      def parent_rank_select(connection, minimum_role)
        recordings = connection.quote_table_name(RecordingStudio::Recording.table_name)
        access_table = connection.quote_table_name(RecordingStudio::Access.table_name)
        <<~SQL.squish
          SELECT 1
          FROM #{recordings} grant_rec
          INNER JOIN #{recordings} grant_parent ON grant_parent.id = grant_rec.parent_recording_id
          WHERE grant_rec.recordable_id = #{access_table}.id
            AND grant_rec.recordable_type = #{connection.quote('RecordingStudio::Access')}
            AND #{rank_comparison_sql(connection, access_table, minimum_role)}
        SQL
      end

      def rank_comparison_sql(connection, access_table, minimum_role)
        role_sql = "#{access_table}.role"
        type_sql = "grant_parent.recordable_type"
        "#{RoleRegistry.rank_sql(connection, role_sql, type_sql)} >= " \
          "#{RoleRegistry.minimum_sql(connection, minimum_role, type_sql)}"
      end
    end
  end
end
