# frozen_string_literal: true

# Wall time and SQL statement counts for access checks on one seeded tree.
#
# Run from the dummy app, twice, on the same rows:
#
#   bin/rails runner script/benchmark_access.rb before
#   bin/rails runner script/benchmark_access.rb after
#
# The first run creates the tree if it is missing and reuses it after that.
# `before` and `after` are labels for the result file. They do not change the work.
#
# Measured work: authorized?, role_for, authorized_recording_ids, recordings_for,
# root_recordings_for, actors_with_access, shared_with, and the manage-access page.
# Each figure is the median of 5 timed runs after one warmup. SQL time is the sum
# of sql.active_record durations inside the timed region, excluding schema,
# transaction, and cached statements.

require "action_dispatch/testing/integration"
require "digest"
require "json"

LABEL = ARGV[0].presence || "run"
RUNS = 5
ROOTS = 6
FOLDERS_PER_ROOT = 8
PAGES_PER_FOLDER = 40
ACTORS = 24
USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
             "(KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"

module BenchAccess
  module_function

  def prepare!
    ActiveRecord::Base.logger = nil
    Rails.logger.level = :error if Rails.logger
    ActionController::Base.allow_forgery_protection = false
    silence_query_tags!
    RecordingStudioAccessible.configuration.shared_item_resolver = lambda { |recording:|
      { title: recording.recordable_type.to_s, url: "/bench/#{recording.id}" }
    }
    @admin = upsert_user("bench-access-admin@example.com")
    Current.actor = @admin
    @actors = ACTORS.times.map { |index| upsert_user("bench-access-actor-#{index}@example.com") }
    @roots = ROOTS.times.map { |index| ensure_root(index) }
    @folders = @roots.flat_map { |root| folders_for(root) }
    @pages = @folders.flat_map { |folder| pages_for(folder) }
    @targets = sample_targets
    install_resolver_for_custom_case
  end

  def silence_query_tags!
    return unless defined?(ActiveRecord::QueryLogs)

    ActiveRecord::QueryLogs.define_singleton_method(:call) { |sql, _connection = nil| sql }
  end

  def install_resolver_for_custom_case
    # The dummy press kit declares download at boot. Clear it so the
    # no-custom run keeps the three-branch rank SQL. The custom run
    # puts download on Folder, which is the type this dataset grants on.
    PressKit.clear_accessible_roles! if defined?(PressKit) && PressKit.respond_to?(:clear_accessible_roles!)
    Folder.clear_accessible_roles! if Folder.instance_variable_defined?(:@accessible_role_set)
    return unless custom_case? && Folder.respond_to?(:accessible_roles)

    Folder.accessible_roles :view, :download, :edit, :admin
  end

  def custom_case?
    ENV["BENCH_CUSTOM"] == "1"
  end

  def upsert_user(email)
    user = User.find_or_initialize_by(email: email)
    if user.new_record?
      user.password = "Password"
      user.password_confirmation = "Password"
    end
    user.confirmed_at ||= Time.current if user.respond_to?(:confirmed_at=)
    user.save! if user.changed?
    user
  end

  def ensure_root(index)
    name = "Bench access #{index}"
    workspace = Workspace.find_by(name: name) || Workspace.create!(name: name)
    recording = RecordingStudio.root_recording_for(workspace) || create_root!(workspace)
    ensure_owner!(recording)
    recording
  end

  def create_root!(recordable)
    RecordingStudio.create_root_recording!(recordable, actor: @admin, impersonator: nil, metadata: {})
  end

  def ensure_owner!(recording)
    return if RecordingStudioAccessible.authorized?(actor: @admin, recording: recording, role: :admin)

    RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: @admin)
  end

  def folders_for(root)
    workspace = root.recordable
    FOLDERS_PER_ROOT.times.map do |index|
      name = "Bench folder #{index}"
      folder = workspace.folders.find_by(name: name) ||
               workspace.folders.create!(name: name, summary: name, position: index)
      find_child(root, folder) || root.record(folder, parent_recording: root, actor: @admin)
    end
  end

  def pages_for(folder_recording)
    folder = folder_recording.recordable
    PAGES_PER_FOLDER.times.map do |index|
      title = "Bench page #{index}"
      page = folder.pages.find_by(title: title) ||
             folder.pages.create!(title: title, summary: title, position: index)
      find_child(folder_recording, page) ||
        RecordingStudio.root_recording_or_self(folder_recording).record(
          page, parent_recording: folder_recording, actor: @admin
        )
    end
  end

  def find_child(parent, recordable)
    RecordingStudio::Recording.unscoped.find_by(
      recordable: recordable,
      parent_recording_id: parent.id
    )
  end

  def sample_targets
    pages = @pages
    {
      deep_pages: pages.sample(80, random: Random.new(7)),
      list_root: @roots.first,
      list_actor: @actors.first,
      folder: @folders.first,
      share_actor: @actors[3]
    }
  end

  def seed_grants!
    roles = %w[view edit admin]
    @roots.each_with_index do |root, index|
      4.times do |offset|
        actor = @actors[(index + offset) % @actors.length]
        ensure_grant(root, actor, roles[offset % roles.length])
      end
    end
    @folders.each_with_index do |folder, index|
      ensure_grant(folder, @actors[index % @actors.length], index.even? ? "view" : "edit")
      ensure_grant(folder, @actors[(index + 5) % @actors.length], "view")
    end
    # Page does not accept access children. Grants sit on workspaces and folders.
    # Page checks still walk those ancestor grants.
    seed_custom_grants! if custom_case?
  end

  def seed_custom_grants!
    kit = @folders.last
    ensure_grant(kit, @actors.last, "download")
    section = @pages.find { |page| page.parent_recording_id == kit.id }
    @custom = { kit: kit, section: section, actor: @actors.last }
  end

  def ensure_grant(recording, actor, role)
    existing = RecordingStudioAccessible::DirectAccessQuery.access_recordings_for_actor(
      recording: recording, actor: actor
    )
    return if existing.exists?

    RecordingStudioAccessible::AccessCreationContext.allow do
      recording.root_recording_or_self.record(
        RecordingStudio::Access,
        parent_recording: recording,
        actor: @admin
      ) do |access|
        access.actor = actor
        access.role = role
      end
    end
  end

  def dataset
    {
      content_recordings: @roots.length + @folders.length + @pages.length,
      roots: @roots.length,
      folders: @folders.length,
      pages: @pages.length,
      actors: @actors.length + 1,
      access_recordings: RecordingStudio::Recording.unscoped.where(
        recordable_type: "RecordingStudio::Access",
        root_recording_id: @roots.map(&:id)
      ).count,
      custom: custom_case?
    }
  end

  def scenarios
    actor = @targets[:list_actor]
    root = @targets[:list_root]
    folder = @targets[:folder]
    pages = @targets[:deep_pages]
    share_actor = @targets[:share_actor]
    list = {
      "authorized?" => lambda do
        pages.each { |page| RecordingStudioAccessible.authorized?(actor: actor, recording: page, role: :view) }
        pages.length
      end,
      "role_for" => lambda do
        pages.each { |page| RecordingStudioAccessible.role_for(actor: actor, recording: page) }
        pages.length
      end,
      "authorized_recording_ids" => lambda do
        ids = RecordingStudioAccessible.authorized_recording_ids(actor: actor, root: root, role: :view).pluck(:id)
        ids.length
      end,
      "recordings_for" => lambda do
        ids = RecordingStudioAccessible.recordings_for(
          actor: actor, parent_recording: root, minimum_role: :view
        ).pluck(:id)
        ids.length
      end,
      "root_recordings_for" => lambda do
        rows = RecordingStudioAccessible.root_recordings_for(actor: actor, minimum_role: :view)
        rows.length
      end,
      "actors_with_access" => lambda do
        rows = RecordingStudioAccessible.actors_with_access(recording: folder, minimum_role: :view)
        rows.length
      end,
      "shared_with" => lambda do
        page = RecordingStudioAccessible.shared_with(actor: share_actor)
        page.respond_to?(:items) ? page.items.length : Array(page).length
      end,
      "manage_access" => lambda do
        status, body = manage_access_status(root)
        unless status == 200
          title = body.to_s[/<h1>(.*?)<\/h1>/m, 1].to_s.gsub(/\s+/, " ")[0, 180]
          raise "manage access status #{status} #{title}"
        end

        status
      end
    }
    if custom_case? && @custom
      kit = @custom[:kit]
      person = @custom[:actor]
      list["authorized_download"] = lambda do
        allowed = RecordingStudioAccessible.authorized?(actor: person, recording: kit, role: :download)
        view = RecordingStudioAccessible.authorized?(actor: person, recording: @custom[:section], role: :view)
        [allowed, view]
      end
    end
    list
  end

  def manage_access_status(recording)
    session = @session ||= ActionDispatch::Integration::Session.new(Rails.application)
    session.host! "localhost"
    session.post(
      "/users/sign_in",
      params: { user: { email: @admin.email, password: "Password" } },
      headers: { "User-Agent" => USER_AGENT }
    )
    session.get(
      "/recording_studio_accessible/recordings/#{recording.id}/accesses",
      headers: { "User-Agent" => USER_AGENT }
    )
    [session.response.status, session.response.body]
  end

  def measure_all
    scenarios.each_key { |name| time_once(scenarios.fetch(name)) }
    scenarios.map do |name, work|
      samples = RUNS.times.map { time_once(work) }
      summarize(name, samples)
    end
  end

  def time_once(work)
    GC.start
    ActiveRecord::Base.connection.clear_query_cache
    queries = 0
    sql_ms = 0.0
    errors = 0
    result = nil
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_n, start, finish, _id, payload|
      next if payload[:cached] || payload[:name] == "SCHEMA" || payload[:name] == "TRANSACTION"

      queries += 1
      sql_ms += (finish - start) * 1000.0
    end
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    begin
      result = work.call
    rescue StandardError
      errors += 1
      raise
    ensure
      wall_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000.0
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
    { wall_ms: wall_ms, sql_ms: sql_ms, queries: queries, errors: errors, result: result }
  end

  def summarize(name, samples)
    walls = samples.map { |sample| sample[:wall_ms] }
    sqls = samples.map { |sample| sample[:sql_ms] }
    {
      operation: name,
      runs: samples.length,
      wall_ms_median: median(walls),
      wall_ms_min: walls.min,
      wall_ms_max: walls.max,
      sql_ms_median: median(sqls),
      queries: samples.map { |sample| sample[:queries] }.uniq,
      errors: samples.sum { |sample| sample[:errors] },
      result: samples.last[:result]
    }
  end

  def median(values)
    ordered = values.sort
    mid = ordered.length / 2
    return ordered[mid] if ordered.length.odd?

    (ordered[mid - 1] + ordered[mid]) / 2.0
  end

  def direct_access_query
    RecordingStudioAccessible::DirectAccessQuery
  end

  def write!(rows)
    payload = {
      label: LABEL,
      git: `git -C #{Rails.root.join("../..")} rev-parse --short HEAD`.strip,
      dataset: dataset,
      rows: rows,
      recorded_at: Time.now.utc.iso8601
    }
    directory = ENV.fetch("BENCH_OUT", "/opt/cursor/artifacts")
    FileUtils.mkdir_p(directory)
    path = File.join(directory, "benchmark-access-#{LABEL}.json")
    File.write(path, JSON.pretty_generate(payload))
    warn "wrote #{path}"
    rows.each do |row|
      warn format(
        "%-28s wall median %8.1f ms (%6.1f..%6.1f) sql median %8.1f ms queries %s result %s errors %d",
        row[:operation], row[:wall_ms_median], row[:wall_ms_min], row[:wall_ms_max],
        row[:sql_ms_median], row[:queries].inspect, row[:result].inspect, row[:errors]
      )
    end
  end
end

BenchAccess.prepare!
BenchAccess.seed_grants!
BenchAccess.write!(BenchAccess.measure_all)
