# frozen_string_literal: true

module RecordingStudioAccessible
  # Ids authorized? would allow under one recording.
  #
  # One statement. Recursive CTEs walk parent_recording_id. No child list is
  # built in Ruby. A kept grant covers its recording and descendants reached
  # through parents. A grant on a stored root covers recordings that store
  # that root, including when the root sits off the parent chain, and does
  # not cover descendants that do not store it and do not inherit it.
  # Audience rules are not read. Trashed recordings stay in the set when
  # authorized? would allow them. Trashed grants and dependent grants that
  # fail DependentAccess.effective? stay out. The manager walk matches
  # EffectiveRootIds.
  class AuthorizedRecordingIds
    def self.relation_for(actor:, root:, role:, recordable_type:)
      new(actor: actor, root: root, role: role, recordable_type: recordable_type).relation
    end

    def initialize(actor:, root:, role:, recordable_type:)
      @actor = actor
      @root = root
      @minimum = Integer(RecordingStudio::AccessRoles.value_for(role))
      @recordable_type = recordable_type
    end

    def relation
      quoted = connection.quote_table_name(RecordingStudio::Recording.table_name)
      RecordingStudio::Recording.unscoped
                                .from(Arel.sql("(#{statement}) AS #{quoted}(id)"))
                                .reselect("#{quoted}.id")
                                .distinct
    end

    private

    def statement
      "WITH RECURSIVE #{cte_list.join(', ')} #{final_select}"
    end

    def cte_list
      parts = [lookup_cte, tree_cte, relevant_parents_cte, candidates_cte]
      parts << grant_walk_cte if dependent_column?
      parts << effective_nodes_cte
      parts.push(chain_seeds_cte, chain_covered_cte, root_covered_cte)
    end

    def lookup_cte
      "lookup AS (#{lookup_sql})"
    end

    def tree_cte
      "tree AS (#{tree_sql})"
    end

    def relevant_parents_cte
      "relevant_parents AS (#{relevant_parents_sql})"
    end

    def candidates_cte
      "candidates AS (#{candidates_sql})"
    end

    def grant_walk_cte
      "grant_walk AS (#{grant_walk_sql})"
    end

    def effective_nodes_cte
      "effective_nodes AS (#{effective_nodes_sql})"
    end

    def chain_seeds_cte
      "chain_seeds AS (#{chain_seeds_sql})"
    end

    def chain_covered_cte
      "chain_covered AS (#{chain_covered_sql})"
    end

    def root_covered_cte
      "root_covered AS (#{root_covered_sql})"
    end

    def lookup_sql
      <<~SQL.squish
        SELECT id, parent_recording_id, #{id_array('id')} AS seen
        FROM #{recordings}
        WHERE id = #{root_sql}
        UNION ALL
        SELECT parent.id, parent.parent_recording_id, lookup.seen || parent.id
        FROM #{recordings} parent
        INNER JOIN lookup ON lookup.parent_recording_id = parent.id
        WHERE NOT (parent.id = ANY(lookup.seen))
      SQL
    end

    def tree_sql
      <<~SQL.squish
        SELECT id, parent_recording_id, #{id_array('id')} AS seen
        FROM #{recordings}
        WHERE id = #{root_sql}
        UNION ALL
        SELECT child.id, child.parent_recording_id, tree.seen || child.id
        FROM #{recordings} child
        INNER JOIN tree ON child.parent_recording_id = tree.id
        WHERE NOT (child.id = ANY(tree.seen))
      SQL
    end

    def relevant_parents_sql
      <<~SQL.squish
        SELECT id FROM tree
        UNION
        SELECT id FROM lookup
        UNION
        SELECT COALESCE(node.root_recording_id, node.id)
        FROM #{recordings} node
        INNER JOIN tree ON tree.id = node.id
      SQL
    end

    def candidates_sql
      <<~SQL.squish
        SELECT rec.id AS id,
               rec.parent_recording_id AS parent_recording_id,
               rec.root_recording_id AS root_recording_id,
               #{depends_on_select}
               acc.role AS role
        FROM #{recordings} rec
        INNER JOIN #{accesses} acc ON acc.id = rec.recordable_id
        WHERE rec.recordable_type = #{access_type_sql}
          AND #{RecordingStudio.kept_sql('rec')}
          AND acc.actor_type = #{actor_type_sql}
          AND acc.actor_id = #{actor_id_sql}
          AND #{role_rank_sql('TRIM(acc.role)')} >= #{@minimum}
          AND rec.parent_recording_id IN (SELECT id FROM relevant_parents)
      SQL
    end

    def depends_on_select
      return "" unless dependent_column?

      "acc.depends_on_recording_id AS depends_on_recording_id,"
    end

    def grant_walk_sql
      "#{grant_seed_sql} UNION ALL #{grant_step_sql}"
    end

    # Names are fixed by this first select. The recursive step reads them.
    def grant_seed_sql
      <<~SQL.squish
        SELECT candidates.id AS id,
               candidates.parent_recording_id AS parent_recording_id,
               COALESCE(candidates.root_recording_id, candidates.id) AS node_root_id,
               candidates.depends_on_recording_id AS depends_on_recording_id,
               candidates.role AS node_role,
               #{id_array('candidates.id')} AS seen,
               (candidates.depends_on_recording_id IS NULL) AS done
        FROM candidates
      SQL
    end

    def grant_step_sql
      <<~SQL.squish
        SELECT grant_walk.id,
               grant_walk.parent_recording_id,
               COALESCE(manager.root_recording_id, manager.id),
               manager_access.depends_on_recording_id,
               manager_access.role,
               grant_walk.seen || manager.id,
               (manager_access.depends_on_recording_id IS NULL)
        FROM grant_walk
        INNER JOIN #{recordings} manager ON manager.id = grant_walk.depends_on_recording_id
        INNER JOIN #{accesses} manager_access ON manager_access.id = manager.recordable_id
        WHERE #{step_filters_sql}
      SQL
    end

    def step_filters_sql
      [
        "NOT grant_walk.done",
        "manager.recordable_type = #{access_type_sql}",
        RecordingStudio.kept_sql("manager"),
        "NOT (manager.id = ANY(grant_walk.seen))",
        "COALESCE(manager.root_recording_id, manager.id) = grant_walk.node_root_id",
        "#{role_rank_sql('manager_access.role')} >= #{role_rank_sql('grant_walk.node_role')}"
      ].join(" AND ")
    end

    def effective_nodes_sql
      if dependent_column?
        finished_grant_sql
      else
        independent_grant_sql
      end
    end

    def finished_grant_sql
      <<~SQL.squish
        SELECT DISTINCT grant_walk.parent_recording_id AS node_id
        FROM grant_walk
        WHERE grant_walk.done AND grant_walk.parent_recording_id IS NOT NULL
      SQL
    end

    def independent_grant_sql
      <<~SQL.squish
        SELECT DISTINCT candidates.parent_recording_id AS node_id
        FROM candidates
        WHERE candidates.parent_recording_id IS NOT NULL
      SQL
    end

    def chain_seeds_sql
      <<~SQL.squish
        SELECT effective_nodes.node_id AS id
        FROM effective_nodes
        INNER JOIN tree ON tree.id = effective_nodes.node_id
        UNION
        SELECT #{root_sql} AS id
        WHERE EXISTS (
          SELECT 1
          FROM effective_nodes
          INNER JOIN lookup ON lookup.id = effective_nodes.node_id
        )
      SQL
    end

    def chain_covered_sql
      <<~SQL.squish
        SELECT chain_seeds.id AS id FROM chain_seeds
        UNION
        SELECT child.id
        FROM tree child
        INNER JOIN chain_covered ON child.parent_recording_id = chain_covered.id
      SQL
    end

    def root_covered_sql
      <<~SQL.squish
        SELECT tree.id AS id
        FROM tree
        INNER JOIN #{recordings} node ON node.id = tree.id
        INNER JOIN effective_nodes
          ON effective_nodes.node_id = COALESCE(node.root_recording_id, node.id)
      SQL
    end

    def final_select
      <<~SQL.squish
        SELECT covered.id
        FROM (
          SELECT chain_covered.id FROM chain_covered
          UNION
          SELECT root_covered.id FROM root_covered
        ) covered
        INNER JOIN #{recordings} chosen ON chosen.id = covered.id
        #{type_filter_sql}
      SQL
    end

    def type_filter_sql
      return "" if @recordable_type.nil?

      "WHERE chosen.recordable_type = #{connection.quote(@recordable_type)}"
    end

    def role_rank_sql(expression)
      branches = RecordingStudio::AccessRoles::ORDER.map do |name, rank|
        "WHEN #{connection.quote(name)} THEN #{Integer(rank)}"
      end
      "CASE #{expression} #{branches.join(' ')} END"
    end

    def id_array(expression)
      "ARRAY[#{expression}]::#{id_sql_type}[]"
    end

    def id_sql_type
      type = RecordingStudio::Recording.columns_hash.fetch("id").sql_type
      raise ArgumentError, "unsupported id type" unless type.match?(/\A[a-z0-9_]+\z/)

      type
    end

    def root_sql
      "#{connection.quote(@root.id)}::#{id_sql_type}"
    end

    def actor_type_sql
      connection.quote(RecordingStudioAccessible::ActorType.for(@actor))
    end

    def actor_id_sql
      connection.quote(@actor.id)
    end

    def access_type_sql
      connection.quote("RecordingStudio::Access")
    end

    def dependent_column?
      return @dependent_column if defined?(@dependent_column)

      @dependent_column = RecordingStudioAccessible::DependentAccess.column_available?
    end

    def recordings
      quote_table(RecordingStudio::Recording.table_name)
    end

    def accesses
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
