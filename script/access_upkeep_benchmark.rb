# frozen_string_literal: true

# Postgres 16 dummy-data benchmark for the access upkeep hotspots.
# Query cache is on. About 46,500 recordings, 5,355 kept access grants,
# 320 actors. Run from test/dummy:
#
#   DB_NAME=accessible_upkeep_benchmark DB_PASSWORD=postgres \
#     bin/rails runner ../../script/access_upkeep_benchmark.rb
#
# Prints milliseconds and query counts. Writes roll back.

KEPT_GRANTS = 5_355
ACTORS = 320
DUPLICATE_PAIRS = 50
DEPENDENT_GRANTS = 400
TRASHED_GRANTS = 80
RULES = 200
DISALLOWED_RULES = 150
TARGET_RECORDINGS = 46_500
ACTION = "bench.kit"

ActiveRecord::Base.logger = nil
QUERY_CACHE_MAX = 20_000
pool = ActiveRecord::Base.connection_pool
pool.instance_variable_set(:@query_cache_max_size, QUERY_CACHE_MAX)
registry = pool.instance_variable_get(:@thread_query_caches)
registry.instance_variable_get(:@map)[ActiveSupport::IsolatedExecutionState.context] =
  ActiveRecord::ConnectionAdapters::QueryCache::Store.new(
    pool.instance_variable_get(:@query_cache_version),
    QUERY_CACHE_MAX
  )

def connection
  ActiveRecord::Base.connection
end

def seed!
  return if RecordingStudio::Recording.count >= TARGET_RECORDINGS - 50

  now = Time.current
  connection.execute(<<~SQL)
    INSERT INTO users (id, email, encrypted_password, registered_with, confirmed_at, created_at, updated_at)
    SELECT gen_random_uuid(), 'bench-' || i || '@example.com', 'benchmark', 'password', #{connection.quote(now)}, #{connection.quote(now)}, #{connection.quote(now)}
    FROM generate_series(1, #{ACTORS}) AS series(i)
  SQL
  user_ids = connection.select_values("SELECT id FROM users WHERE email LIKE 'bench-%@example.com' ORDER BY email")

  workspace_id = connection.select_value(<<~SQL)
    INSERT INTO workspaces (id, name, created_at, updated_at)
    VALUES (gen_random_uuid(), 'Benchmark workspace', #{connection.quote(now)}, #{connection.quote(now)})
    RETURNING id
  SQL
  root_id = connection.select_value(<<~SQL)
    INSERT INTO recording_studio_recordings (
      id, recordable_type, recordable_id, parent_recording_id, root_recording_id, created_at, updated_at
    ) VALUES (
      gen_random_uuid(), 'Workspace', #{connection.quote(workspace_id)}, NULL, NULL,
      #{connection.quote(now)}, #{connection.quote(now)}
    ) RETURNING id
  SQL
  connection.execute(<<~SQL)
    UPDATE recording_studio_recordings
    SET root_recording_id = id
    WHERE id = #{connection.quote(root_id)}
  SQL

  page_count = TARGET_RECORDINGS - 1 - KEPT_GRANTS - TRASHED_GRANTS - RULES
  connection.execute(<<~SQL)
    INSERT INTO recording_studio_recordings (
      id, recordable_type, recordable_id, parent_recording_id, root_recording_id, created_at, updated_at
    )
    SELECT gen_random_uuid(), 'Page', gen_random_uuid(), #{connection.quote(root_id)}, #{connection.quote(root_id)},
           #{connection.quote(now)}, #{connection.quote(now)}
    FROM generate_series(1, #{page_count})
  SQL

  parent_ids = connection.select_values(<<~SQL)
    SELECT id FROM recording_studio_recordings
    WHERE recordable_type = 'Page'
    ORDER BY id
    LIMIT #{KEPT_GRANTS - DUPLICATE_PAIRS + TRASHED_GRANTS}
  SQL

  kept_parents = parent_ids.first(KEPT_GRANTS - DUPLICATE_PAIRS)
  duplicate_parents = kept_parents.first(DUPLICATE_PAIRS)
  trashed_parents = parent_ids.last(TRASHED_GRANTS)
  admin_id = user_ids.first

  insert_grants(kept_parents, user_ids, admin_id, root_id, trashed: false, now: now)
  insert_grants(duplicate_parents, user_ids, admin_id, root_id, trashed: false, now: now, duplicate: true)
  insert_grants(trashed_parents, user_ids, admin_id, root_id, trashed: true, now: now)

  manager_id = connection.select_value(<<~SQL)
    SELECT recording_studio_recordings.id
    FROM recording_studio_recordings
    INNER JOIN recording_studio_accesses
      ON recording_studio_accesses.id = recording_studio_recordings.recordable_id
    WHERE recording_studio_recordings.recordable_type = 'RecordingStudio::Access'
      AND recording_studio_recordings.trashed_at IS NULL
      AND recording_studio_accesses.role = 'view'
      AND recording_studio_accesses.depends_on_recording_id IS NULL
    ORDER BY recording_studio_recordings.id
    LIMIT 1
  SQL
  connection.execute(<<~SQL)
    UPDATE recording_studio_accesses
    SET depends_on_recording_id = #{connection.quote(manager_id)}
    WHERE id IN (
      SELECT recording_studio_accesses.id
      FROM recording_studio_accesses
      INNER JOIN recording_studio_recordings
        ON recording_studio_recordings.recordable_id = recording_studio_accesses.id
       AND recording_studio_recordings.recordable_type = 'RecordingStudio::Access'
      WHERE recording_studio_recordings.trashed_at IS NULL
        AND recording_studio_accesses.role = 'view'
        AND recording_studio_recordings.id <> #{connection.quote(manager_id)}
      ORDER BY recording_studio_accesses.id
      LIMIT #{DEPENDENT_GRANTS}
    )
  SQL
  connection.execute(<<~SQL)
    UPDATE recording_studio_recordings
    SET parent_recording_id = #{connection.quote(root_id)}
    WHERE recordable_type = 'RecordingStudio::Access'
      AND recordable_id IN (
        SELECT id FROM recording_studio_accesses
        WHERE depends_on_recording_id IS NOT NULL
      )
  SQL

  connection.execute(<<~SQL)
    INSERT INTO recording_studio_access_rules (id, action, audience, created_at)
    SELECT gen_random_uuid(), #{connection.quote(ACTION)},
           CASE WHEN series.i <= #{DISALLOWED_RULES} THEN 'public' ELSE 'granted' END,
           #{connection.quote(now)}
    FROM generate_series(1, #{RULES}) AS series(i)
  SQL
  connection.execute(<<~SQL)
    INSERT INTO recording_studio_recordings (
      id, recordable_type, recordable_id, parent_recording_id, root_recording_id, created_at, updated_at
    )
    SELECT gen_random_uuid(), 'RecordingStudio::AccessRule', recording_studio_access_rules.id,
           #{connection.quote(root_id)}, #{connection.quote(root_id)},
           #{connection.quote(now)}, #{connection.quote(now)}
    FROM recording_studio_access_rules
    WHERE action = #{connection.quote(ACTION)}
  SQL

  puts "seeded recordings=#{RecordingStudio::Recording.count} " \
       "kept_grants=#{kept_grant_count} actors=#{ACTORS}"
end

def insert_grants(parent_ids, user_ids, admin_id, root_id, trashed:, now:, duplicate: false)
  return if parent_ids.empty?

  rows = parent_ids.each_with_index.map do |parent_id, index|
    actor_id = if parent_id == root_id
                 admin_id
               else
                 user_ids[index % user_ids.length]
               end
    role = if !duplicate && index.zero? && !trashed
             "admin"
           elsif duplicate
             "admin"
           else
             "view"
           end
    access_id = SecureRandom.uuid
    recording_id = SecureRandom.uuid
    trashed_at = trashed ? now : nil
    {
      access_id: access_id,
      recording_id: recording_id,
      parent_id: parent_id,
      actor_id: actor_id,
      role: role,
      trashed_at: trashed_at
    }
  end

  # The first kept grant sits on the workspace root so constraint checks have an admin.
  if !duplicate && !trashed
    rows.first[:parent_id] = root_id
    rows.first[:actor_id] = admin_id
    rows.first[:role] = "admin"
  end

  access_values = rows.map do |row|
    "(#{connection.quote(row[:access_id])}, #{connection.quote(row[:actor_id])}, 'User', " \
      "#{connection.quote(row[:role])}, #{connection.quote(now)})"
  end
  connection.execute(<<~SQL)
    INSERT INTO recording_studio_accesses (id, actor_id, actor_type, role, created_at)
    VALUES #{access_values.join(", ")}
  SQL

  recording_values = rows.map do |row|
    "(#{connection.quote(row[:recording_id])}, 'RecordingStudio::Access', #{connection.quote(row[:access_id])}, " \
      "#{connection.quote(row[:parent_id])}, #{connection.quote(root_id)}, " \
      "#{connection.quote(row[:trashed_at])}, #{connection.quote(now)}, #{connection.quote(now)})"
  end
  connection.execute(<<~SQL)
    INSERT INTO recording_studio_recordings (
      id, recordable_type, recordable_id, parent_recording_id, root_recording_id, trashed_at, created_at, updated_at
    ) VALUES #{recording_values.join(", ")}
  SQL
end

def kept_grant_count
  RecordingStudio::Recording.unscoped
                            .where(recordable_type: "RecordingStudio::Access", trashed_at: nil)
                            .count
end

def measure(label)
  queries = 0
  cached = 0
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  ActiveRecord::Base.connection.clear_query_cache
  subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
    payload = args.last
    next if payload[:name] == "SCHEMA"
    next if payload[:sql].to_s.match?(/\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE|SELECT 1)\b/i)

    if payload[:cached]
      cached += 1
    else
      queries += 1
    end
  end
  ActiveRecord::Base.cache { yield }
  elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
  puts "#{label}: #{elapsed} ms, #{queries} queries, #{cached} query-cache hits"
ensure
  ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
end

def rollbacking
  RecordingStudio::Recording.transaction do
    yield
    raise ActiveRecord::Rollback
  end
end

seed!

admin = User.find(connection.select_value(<<~SQL))
  SELECT recording_studio_accesses.actor_id
  FROM recording_studio_accesses
  INNER JOIN recording_studio_recordings
    ON recording_studio_recordings.recordable_id = recording_studio_accesses.id
   AND recording_studio_recordings.recordable_type = 'RecordingStudio::Access'
  WHERE recording_studio_accesses.role = 'admin'
    AND recording_studio_recordings.trashed_at IS NULL
    AND recording_studio_recordings.parent_recording_id = recording_studio_recordings.root_recording_id
  ORDER BY recording_studio_accesses.created_at
  LIMIT 1
SQL
root = RecordingStudio::Recording.find_by!(recordable_type: "Workspace")
manager_id = connection.select_value(<<~SQL)
  SELECT depends_on_recording_id
  FROM recording_studio_accesses
  WHERE depends_on_recording_id IS NOT NULL
  LIMIT 1
SQL

RecordingStudioAccessible.configuration.action_audiences[ACTION.to_sym] = {
  allowed: %i[public signed_in granted],
  default: :granted,
  granted_roles: %i[view edit admin],
  granted_override: false,
  manage_role: :admin
}

puts "recordings=#{RecordingStudio::Recording.count} kept_grants=#{kept_grant_count} " \
     "postgres=#{connection.select_value('SHOW server_version')} query_cache_max=#{QUERY_CACHE_MAX}"

measure("integrity") do
  result = RecordingStudioAccessible::Services::AccessGrantIntegrity.call
  raise result.error unless result.success?
end

measure("void_dependents") do
  rollbacking do
    result = RecordingStudioAccessible::Services::VoidDependentAccesses.call(
      manager_access_recording_id: manager_id,
      manager_actor: admin,
      moved: true
    )
    raise result.error.to_s unless result.success?
  end
end

measure("audience_constraint") do
  rollbacking do
    RecordingStudioAccessible.set_audience_constraint!(
      root: root,
      action: ACTION.to_sym,
      allowed_audiences: %i[granted],
      actor: admin
    )
  end
end
