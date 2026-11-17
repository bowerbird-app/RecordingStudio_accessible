# frozen_string_literal: true

module RecordingStudioAccessible
  # Ids authorized? would allow under one recording.
  #
  # A kept grant on a real root, at the requested role, with a valid manager
  # chain, uses Recording.within (for_root). That reads root_recording_id.
  # Recording Studio enforces that column. This query does not check it again.
  #
  # Every other case seeds from the actor's kept grants. The seed query uses
  # the same role rank, kept check, and manager chain as authorized?, then
  # walks parents only. A grant node whose parents reach the requested
  # recording is a seed. A grant on an ancestor seeds the requested recording.
  # Each seed walks its children through parent_recording_id, including the
  # seed. The walk stops when a parent repeats. It does not read
  # root_recording_id and it does not stop at a depth cap.
  #
  # recordings_relation is that same set as rows the caller can order and
  # limit. A root grant still uses Recording.within. A nested anchor is not a
  # root: its children store the workspace id. A subtree the probe has already
  # counted, at most 2,000 ids, is one array predicate. A longer subtree,
  # with or without recordable_type, filters root_recording_id to that
  # workspace. Each row checks ancestry against the seeds. Order by
  # created_at, id and the caller limit stops on
  # (root_recording_id, created_at, id). A type uses
  # (root_recording_id, recordable_type, created_at, id). The filter is one
  # row per recording.
  # Audience rules are not read. Trashed recordings stay in the set when
  # authorized? would allow them. Trashed grants and dependent grants that
  # fail DependentAccess.effective? stay out. The manager walk matches
  # EffectiveRootIds.
  class AuthorizedRecordingIds
    # At or below this many recordings the seeded walk is a short nested loop.
    # Above it, the creation index reaches a limited page without walking the
    # rest. Measured on a root of about 100_000 recordings: both shapes are
    # cheap on their own side of the line, and the other shape is not.
    BROAD_SUBTREE_ROWS = 2_000
    PROBE_DEPTH = 32

    def self.relation_for(actor:, root:, role:, recordable_type:)
      new(actor: actor, root: root, role: role, recordable_type: recordable_type).relation
    end

    def self.recordings_for(actor:, root:, scope:, role:, recordable_type:)
      new(actor: actor, root: root, role: role, recordable_type: recordable_type).recordings_relation(scope)
    end

    def initialize(actor:, root:, role:, recordable_type:)
      @actor = actor
      @root = root
      @role = role
      @minimum = Integer(RecordingStudio::AccessRoles.value_for(role))
      @recordable_type = recordable_type
    end

    def relation
      return within_ids if root_grant_fast_path?

      seeded_relation
    end

    def recordings_relation(scope)
      scoped = typed_scope(scope)
      return scoped.within(@root) if root_grant_fast_path?

      case subtree_shape
      when :empty
        scoped.none
      when :ids
        bound_id_relation(scoped, @bounded_ids)
      else
        keyset_ancestry_relation(scoped)
      end
    end

    private

    def typed_scope(scope)
      return scope if @recordable_type.nil?

      scope.where(recordable_type: @recordable_type)
    end

    # :ids is a finished subtree of at most BROAD_SUBTREE_ROWS. :broad crossed
    # that line. :deep ran out of probe levels before the subtree ended.
    def subtree_shape
      return @subtree_shape if defined?(@subtree_shape)

      seen = {}
      frontier = loaded_seed_ids
      frontier.each { |id| seen[id] = true }
      @subtree_shape = classify_subtree(seen, frontier)
    end

    def classify_subtree(seen, frontier)
      return :empty if seen.empty?
      return :broad if seen.size > BROAD_SUBTREE_ROWS

      probe_subtree(seen, frontier)
    end

    def probe_subtree(seen, frontier)
      PROBE_DEPTH.times do
        frontier = unseen_descendants(seen, frontier)
        return :broad if seen.size > BROAD_SUBTREE_ROWS
        next unless frontier.empty?

        @bounded_ids = seen.keys
        return :ids
      end
      :deep
    end

    def unseen_descendants(seen, frontier)
      fresh = []
      descendant_batch(frontier, BROAD_SUBTREE_ROWS - seen.size + 1).each do |id|
        next if seen[id]

        seen[id] = true
        fresh << id
      end
      fresh
    end

    def bound_id_relation(scope, ids)
      scope.where("#{recordings}.id = ANY(?::#{id_sql_type}[])", "{#{ids.join(',')}}")
    end

    def loaded_seed_ids
      connection.select_values("SELECT id FROM (#{seed_ids_sql}) seed_rows").uniq
    end

    def descendant_batch(frontier, limit)
      connection.select_values(<<~SQL.squish)
        SELECT child.id
        FROM (SELECT id FROM #{recordings} WHERE id IN (#{quoted_id_list(frontier)})) parents
        JOIN LATERAL (
          SELECT id
          FROM #{recordings}
          WHERE parent_recording_id = parents.id
          OFFSET 0
        ) child ON TRUE
        LIMIT #{Integer(limit)}
      SQL
    end

    # Workspace rows, newest first once the caller orders by created_at, id.
    # The per-row ancestry check keeps a sibling of the anchor out.
    def keyset_ancestry_relation(scope)
      scope.with(seed_ids: Arel.sql(seed_ids_sql))
           .where(root_recording_id: @root.root_recording_id)
           .where(ancestry_exists_sql)
    end

    def ancestry_exists_sql
      outer = recordings
      <<~SQL.squish
        EXISTS (
          WITH RECURSIVE ancestry (id, parent_recording_id, seen) AS (
            SELECT #{outer}.id, #{outer}.parent_recording_id, #{id_array("#{outer}.id")}
            UNION ALL
            SELECT parent.id, parent.parent_recording_id, ancestry.seen || parent.id
            FROM #{recordings} parent
            INNER JOIN ancestry ON parent.id = ancestry.parent_recording_id
            WHERE NOT (parent.id = ANY(ancestry.seen))
              AND NOT EXISTS (SELECT 1 FROM seed_ids WHERE seed_ids.id = ancestry.id)
          )
          SELECT 1 FROM ancestry
          INNER JOIN seed_ids ON seed_ids.id = ancestry.id
        )
      SQL
    end

    # A dependent grant needs the manager walk. An actor with none of those
    # gets the same nodes from the grant's parent, and the smaller query stays
    # a short nested loop.
    def seed_ids_sql
      return dependent_seed_ids_sql if dependent_actor_grants?

      independent_seed_ids_sql
    end

    def independent_seed_ids_sql
      granted = actor_grant_sql
      if dependent_column?
        granted = <<~SQL.squish
          SELECT * FROM (#{granted}) granted
          WHERE granted.depends_on_recording_id IS NULL
        SQL
      end
      parts = [
        "candidates AS (#{granted})",
        "effective_nodes AS (#{independent_nodes_sql})",
        "node_ascent AS (#{node_ascent_sql})",
        "request_ascent AS (#{request_ascent_sql})"
      ]
      "WITH RECURSIVE #{parts.join(', ')} #{seed_only_select_sql}"
    end

    def independent_nodes_sql
      <<~SQL.squish
        SELECT candidates.parent_recording_id AS node_id
        FROM candidates
        WHERE candidates.parent_recording_id IS NOT NULL
      SQL
    end

    def dependent_seed_ids_sql
      parts = ["candidates AS (#{actor_grant_sql})"]
      parts << grant_walk_cte if dependent_column?
      parts << effective_nodes_cte
      parts << "node_ascent AS (#{node_ascent_sql})"
      parts << "request_ascent AS (#{request_ascent_sql})"
      "WITH RECURSIVE #{parts.join(', ')} #{seed_only_select_sql}"
    end

    def dependent_actor_grants?
      return @dependent_actor_grants if defined?(@dependent_actor_grants)
      return @dependent_actor_grants = false unless dependent_column?

      @dependent_actor_grants = connection.select_value("SELECT #{dependent_actor_grants_sql}") == true
    end

    def dependent_actor_grants_sql
      <<~SQL.squish
        EXISTS (
          SELECT 1
          FROM #{accesses} acc
          INNER JOIN #{recordings} rec ON rec.recordable_id = acc.id
          WHERE rec.recordable_type = #{access_type_sql}
            AND #{RecordingStudio.kept_sql('rec')}
            AND acc.actor_type = #{actor_type_sql}
            AND acc.actor_id = #{actor_id_sql}
            AND acc.depends_on_recording_id IS NOT NULL
            AND #{role_rank_sql('TRIM(acc.role)')} >= #{@minimum}
        )
      SQL
    end

    def seed_only_select_sql
      <<~SQL.squish
        SELECT node_ascent.origin_id AS id
        FROM node_ascent
        WHERE node_ascent.id = #{root_sql}
        UNION
        SELECT rec.id AS id
        FROM #{recordings} rec
        WHERE rec.id = #{root_sql}
          AND EXISTS (
            SELECT 1
            FROM effective_nodes
            INNER JOIN request_ascent ON request_ascent.id = effective_nodes.node_id
          )
      SQL
    end

    def seeded_relation
      id_relation(seeded_statement)
    end

    def id_relation(body)
      quoted = connection.quote_table_name(RecordingStudio::Recording.table_name)
      RecordingStudio::Recording.unscoped
                                .from(Arel.sql("(#{body}) AS #{quoted}(id)"))
                                .reselect("#{quoted}.id")
                                .distinct
    end

    # within equals the parent walk for a real root. A child grant, a weaker
    # role, or a nested recording keeps the walk above.
    def root_grant_fast_path?
      stored_root? && root_grant?
    end

    def within_ids
      scope = RecordingStudio::Recording.unscoped.within(@root)
      scope = scope.where(recordable_type: @recordable_type) if @recordable_type
      scope.reselect(:id)
    end

    def stored_root?
      @root.parent_recording_id.nil? && @root.root_recording_id == @root.id
    end

    def root_grant?
      RecordingStudioAccessible.authorized?(actor: @actor, recording: @root, role: @role)
    end

    def grant_walk_cte
      "grant_walk AS (#{grant_walk_sql})"
    end

    def effective_nodes_cte
      "effective_nodes AS (#{effective_nodes_sql})"
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

    def type_filter_sql
      return "" if @recordable_type.nil?

      "WHERE chosen.recordable_type = #{connection.quote(@recordable_type)}"
    end

    # Kept grants for this actor at this role. The parent ascent below decides
    # which of them belong to this recording.
    def actor_grant_sql
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
      SQL
    end

    def depends_on_select
      return "" unless dependent_column?

      "acc.depends_on_recording_id AS depends_on_recording_id,"
    end

    def node_ascent_sql
      <<~SQL.squish
        SELECT effective_nodes.node_id AS origin_id,
               rec.id AS id,
               rec.parent_recording_id AS parent_recording_id,
               #{id_array('rec.id')} AS seen
        FROM effective_nodes
        INNER JOIN #{recordings} rec ON rec.id = effective_nodes.node_id
        UNION ALL
        SELECT node_ascent.origin_id,
               parent.id,
               parent.parent_recording_id,
               node_ascent.seen || parent.id
        FROM #{recordings} parent
        INNER JOIN node_ascent ON node_ascent.parent_recording_id = parent.id
        WHERE NOT (parent.id = ANY(node_ascent.seen))
      SQL
    end

    def request_ascent_sql
      <<~SQL.squish
        SELECT id, parent_recording_id, #{id_array('id')} AS seen
        FROM #{recordings}
        WHERE id = #{root_sql}
        UNION ALL
        SELECT parent.id, parent.parent_recording_id, request_ascent.seen || parent.id
        FROM #{recordings} parent
        INNER JOIN request_ascent ON request_ascent.parent_recording_id = parent.id
        WHERE NOT (parent.id = ANY(request_ascent.seen))
      SQL
    end

    def seeded_statement
      <<~SQL.squish
        WITH RECURSIVE covered (id, path) AS (
          SELECT seed.id, #{id_array('seed.id')}
          FROM (#{seed_ids_sql}) seed
          UNION ALL
          SELECT child.id, covered.path || child.id
          FROM covered
          JOIN LATERAL (
            SELECT id
            FROM #{recordings}
            WHERE parent_recording_id = covered.id
            OFFSET 0
          ) child ON TRUE
          WHERE NOT (child.id = ANY(covered.path))
        )
        SELECT covered.id
        FROM covered
        INNER JOIN #{recordings} chosen ON chosen.id = covered.id
        #{type_filter_sql}
      SQL
    end

    def quoted_id_list(ids)
      ids.map { |id| "#{connection.quote(id)}::#{id_sql_type}" }.join(", ")
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
