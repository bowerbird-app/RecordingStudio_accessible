# frozen_string_literal: true

module RecordingStudioAccessible
  # Parent-chain id walk used when a root grant cannot use Recording.within.
  #
  # The walk stays out of the caller's plan. Postgres compiles every branch it
  # can see, including one a one-time filter will not run, and that compile
  # dominates a root-grant page. A plpgsql function is planned only when the
  # statement calls it.
  class ParentChainIdsFunction
    def self.install!
      return unless tables_ready?

      sql = definition
      return if @definition == sql

      RecordingStudio::Recording.connection.execute(drop_sql)
      RecordingStudio::Recording.connection.execute(sql)
      @definition = sql
    end

    def self.tables_ready?
      connection = RecordingStudio::Recording.connection
      connection.data_source_exists?(RecordingStudio::Recording.table_name) &&
        connection.data_source_exists?(RecordingStudio::Access.table_name)
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
      false
    end

    def self.definition
      "#{signature} #{body}"
    end

    def self.drop_sql
      id_type = sql_type(RecordingStudio::Recording, "id")
      actor_id_type = sql_type(RecordingStudio::Access, "actor_id")
      function = AuthorizedRecordingIds::PARENT_CHAIN_FUNCTION
      "DROP FUNCTION IF EXISTS #{function}(#{id_type}, text, #{actor_id_type}, integer, text)"
    end

    def self.signature
      id_type = sql_type(RecordingStudio::Recording, "id")
      actor_id_type = sql_type(RecordingStudio::Access, "actor_id")
      names = AuthorizedRecordingIds
      <<~SQL.squish
        CREATE OR REPLACE FUNCTION #{names::PARENT_CHAIN_FUNCTION}(
          #{names::PARAM_ROOT} #{id_type},
          #{names::PARAM_ACTOR_TYPE} text,
          #{names::PARAM_ACTOR_ID} #{actor_id_type},
          #{names::PARAM_MINIMUM} integer,
          #{names::PARAM_RECORDABLE_TYPE} text
        ) RETURNS SETOF #{id_type}
        LANGUAGE plpgsql
        COST 100
      SQL
    end

    def self.body
      <<~SQL
        AS $accessible$
        DECLARE
          previous text;
        BEGIN
          previous := current_setting('jit');
          PERFORM set_config('jit', 'off', true);
          RETURN QUERY
          #{AuthorizedRecordingIds.parent_chain_sql};
          PERFORM set_config('jit', previous, true);
        END;
        $accessible$
      SQL
    end

    def self.sql_type(model, column)
      type = model.columns_hash.fetch(column).sql_type
      raise ArgumentError, "unsupported #{column} type" unless type.match?(/\A[a-z0-9_]+\z/)

      type
    end
    private_class_method :sql_type
  end
end
