# frozen_string_literal: true

require "test_helper"

class GrantLookupParityTest < ActiveSupport::TestCase
  KIT = :"parity.kit"

  setup do
    @previous_audiences = RecordingStudioAccessible.configuration.action_audiences.to_h
    RecordingStudioAccessible.configuration.action_audiences[KIT] = {
      allowed: %i[public signed_in granted],
      default: :public,
      granted_roles: %i[view edit admin],
      granted_override: false,
      manage_role: :admin
    }

    @admin = create_user("parity-admin@example.com")
    @editor = create_user("parity-editor@example.com")
    @viewer = create_user("parity-viewer@example.com")
    @outsider = create_user("parity-outsider@example.com")
    @blocked = create_user("parity-blocked@example.com")
    @covered = create_user("parity-covered@example.com")
    @trashed_actor = create_user("parity-trashed@example.com")
    @workspace_actor = Workspace.create!(name: "Parity Workspace Actor")

    @workspace = Workspace.create!(name: "Parity Workspace")
    @root = create_root_recording(@workspace)
    folder = Folder.create!(workspace: @workspace, name: "Parity Folder", summary: "Folder", position: 0)
    @folder = create_child_recording(recordable: folder, parent_recording: @root)

    @admin_grant = create_direct_access_recording(actor: @admin, role: :admin, parent_recording: @root)
    create_direct_access_recording(actor: @editor, role: :edit, parent_recording: @root)
    create_direct_access_recording(actor: @viewer, role: :view, parent_recording: @folder)
    create_direct_access_recording(actor: @workspace_actor, role: :edit, parent_recording: @root)
    trashed = create_direct_access_recording(actor: @trashed_actor, role: :admin, parent_recording: @folder)
    trashed.update_column(:trashed_at, Time.current)

    @manager = create_direct_access_recording(actor: @admin, role: :admin, parent_recording: @folder)
    @blocked_grant = grant_dependent(actor: @blocked, role: :view, parent: @folder, manager: @manager)
    grant_dependent(actor: @covered, role: :view, parent: @folder, manager: @manager)
    create_direct_access_recording(actor: @covered, role: :view, parent_recording: @root)
    @manager.update_column(:trashed_at, Time.current)
  end

  teardown do
    RecordingStudioAccessible.configuration.action_audiences.replace(@previous_audiences)
  end

  test "batched effective roles match role_for across allow, deny, dependents, and trash" do
    lookup = RecordingStudioAccessible::ActorsWithAccess.new(@folder)
    actors = [@admin, @editor, @viewer, @outsider, @blocked, @covered, @trashed_actor, @workspace_actor]

    actors.each do |actor|
      assert_same_role RecordingStudioAccessible.role_for(actor: actor, recording: @folder),
                       lookup.effective_role_for(actor),
                       actor.try(:email) || actor.name
    end

    assert_equal :admin, lookup.effective_role_for(@admin)
    assert RecordingStudioAccessible.authorized?(actor: @admin, recording: @folder, role: :admin)
    assert_equal :edit, lookup.effective_role_for(@editor)
    assert RecordingStudioAccessible.authorized?(actor: @editor, recording: @folder, role: :edit)
    refute RecordingStudioAccessible.authorized?(actor: @editor, recording: @folder, role: :admin)
    assert_equal :view, lookup.effective_role_for(@viewer)
    refute RecordingStudioAccessible.authorized?(actor: @viewer, recording: @folder, role: :edit)
    assert_nil lookup.effective_role_for(@outsider)
    refute RecordingStudioAccessible.authorized?(actor: @outsider, recording: @folder, role: :view)
    assert_nil lookup.effective_role_for(@blocked)
    refute RecordingStudioAccessible.authorized?(actor: @blocked, recording: @folder, role: :view)
    assert_equal :view, lookup.effective_role_for(@covered)
    assert_nil lookup.effective_role_for(@trashed_actor)
    assert_equal :edit, lookup.effective_role_for(@workspace_actor)

    listed = lookup.entries.map { |entry| [entry.actor, entry.role] }.to_h
    listed.each do |actor, role|
      assert_equal role, RecordingStudioAccessible.role_for(actor: actor, recording: @folder)
    end
    refute listed.key?(@blocked)
    refute listed.key?(@trashed_actor)
    refute listed.key?(@outsider)
    assert_equal listed.any?, lookup.any_actor?
    assert_equal listed.any? { |_actor, role| role == :admin }, lookup.any_actor?(minimum_role: :admin)

    @folder.update_column(:trashed_at, Time.current)
    trashed_lookup = RecordingStudioAccessible::ActorsWithAccess.new(@folder)
    [@admin, @editor, @viewer, @blocked, @covered, @workspace_actor].each do |actor|
      assert_same_role RecordingStudioAccessible.role_for(actor: actor, recording: @folder),
                       trashed_lookup.effective_role_for(actor)
    end
    assert_equal :view, trashed_lookup.effective_role_for(@viewer)
    assert_equal :admin, trashed_lookup.effective_role_for(@admin)
  end

  test "audience narrowing changes the action check and leaves grant roles alone" do
    before = role_map(@folder)

    RecordingStudioAccessible.set_audience!(recording: @folder, action: KIT, audience: :public, actor: @admin)
    assert_equal :public, RecordingStudioAccessible.effective_audience(recording: @folder, action: KIT)
    assert RecordingStudioAccessible.authorized_action?(actor: nil, action: KIT, recording: @folder)
    assert RecordingStudioAccessible.authorized_action?(actor: @outsider, action: KIT, recording: @folder)
    assert_equal before, role_map(@folder)

    RecordingStudioAccessible.set_audience_constraint!(
      root: @root,
      action: KIT,
      allowed_audiences: %i[granted],
      actor: @admin
    )

    assert_equal :granted, RecordingStudioAccessible.effective_audience(recording: @folder, action: KIT)
    refute RecordingStudioAccessible.authorized_action?(actor: nil, action: KIT, recording: @folder)
    refute RecordingStudioAccessible.authorized_action?(actor: @outsider, action: KIT, recording: @folder)
    assert RecordingStudioAccessible.authorized_action?(actor: @viewer, action: KIT, recording: @folder)
    assert RecordingStudioAccessible.authorized_action?(actor: @editor, action: KIT, recording: @folder)
    assert_equal before, role_map(@folder)
    assert_nil RecordingStudioAccessible.role_for(actor: @blocked, recording: @folder)
  end

  test "manage access rows match a per grant role_for walk" do
    controller = RecordingStudioAccessible::RecordingAccessesController.new
    controller.instance_variable_set(:@recording, @folder)

    direct = controller.send(:build_direct_access_rows)
    inherited = controller.send(:build_inherited_access_rows)

    assert_equal reference_direct_rows(@folder), direct.map { |row| comparable_direct(row) }
    assert_equal reference_inherited_rows(@folder), inherited.map { |row| comparable_inherited(row) }
    assert direct.any? { |row| row[:actor] == @blocked && row[:effective_role].nil? }
    assert inherited.none? { |row| row[:actor] == @blocked }
    assert inherited.any? { |row| row[:actor] == @editor && row[:effective_role] == :edit }
  end

  test "avatar holders match the per parent walk and ignore a trashed grant" do
    view = Object.new
    view.extend(RecordingStudioAccessible::AvatarsHelper)

    assert_equal reference_avatar_ids(@folder, :direct), avatar_ids(view, @folder, :direct)
    assert_equal reference_avatar_ids(@folder, :all), avatar_ids(view, @folder, :all)
    assert_equal reference_avatar_ids(@folder, :effective), avatar_ids(view, @folder, :effective)
    assert_includes avatar_ids(view, @folder, :all), @blocked.id
    refute_includes avatar_ids(view, @folder, :all), @trashed_actor.id
  end

  test "building manage access rows does not call role_for per grant" do
    controller = RecordingStudioAccessible::RecordingAccessesController.new
    controller.instance_variable_set(:@recording, @folder)
    expected = reference_direct_rows(@folder).map { |row| row[:effective_role] }
    calls = 0

    RecordingStudioAccessible.stub(:role_for, ->(**) { calls += 1 }) do
      rows = controller.send(:build_direct_access_rows)
      controller.send(:build_inherited_access_rows)
      assert_equal expected, rows.map { |row| row[:effective_role] }
    end

    assert_equal 0, calls
  end

  test "manage access and the avatar rollup load grants and actors once" do
    controller = RecordingStudioAccessible::RecordingAccessesController.new
    controller.instance_variable_set(:@recording, @folder)
    view = Object.new
    view.extend(RecordingStudioAccessible::AvatarsHelper)

    row_queries = sql_queries do
      ActiveRecord::Base.connection.clear_query_cache
      controller.send(:build_direct_access_rows)
      controller.send(:build_inherited_access_rows)
    end
    avatar_queries = sql_queries do
      ActiveRecord::Base.connection.clear_query_cache
      view.send(:recording_studio_accessible_access_holders, @folder, scope: :all)
    end

    assert_equal 1, grant_queries(row_queries).size
    assert_equal 1, actor_queries(row_queries, "users").size
    assert_operator actor_queries(row_queries, "workspaces").size, :<=, 2
    assert_equal 1, grant_queries(avatar_queries).size
    assert_equal 1, actor_queries(avatar_queries, "users").size
    assert_equal 1, actor_queries(avatar_queries, "workspaces").size
  end

  test "a locked write refreshes the same lookup and rolls back the last admin" do
    lookup = RecordingStudioAccessible::ActorsWithAccess.new(@root)
    assert lookup.any_actor?(minimum_role: :admin)

    assert_raises(RecordingStudioAccessible::LastAdminError) do
      RecordingStudioAccessible::LastAdminGuard.protect!(recordings: [@root]) do
        @admin_grant.update_column(:trashed_at, Time.current)
      end
    end

    assert_nil @admin_grant.reload.trashed_at
    assert lookup.any_actor?(minimum_role: :admin)
    lookup.refresh!
    assert lookup.any_actor?(minimum_role: :admin)
    assert RecordingStudioAccessible::LastAdminGuard.administered?(@root)
  end

  private

  def role_map(recording)
    lookup = RecordingStudioAccessible::ActorsWithAccess.new(recording)
    [@admin, @editor, @viewer, @outsider, @blocked, @covered, @workspace_actor].to_h do |actor|
      [actor.id, [RecordingStudioAccessible.role_for(actor: actor, recording: recording), lookup.effective_role_for(actor)]]
    end
  end

  def comparable_direct(row)
    {
      id: row[:id],
      actor_id: row[:actor].id,
      direct_role: row[:direct_role].to_s,
      effective_role: row[:effective_role]
    }
  end

  def comparable_inherited(row)
    {
      actor_id: row[:actor].id,
      source_id: row[:source_recording].id,
      source_role: row[:source_role].to_s,
      effective_role: row[:effective_role]
    }
  end

  def reference_direct_rows(recording)
    RecordingStudioAccessible::DirectAccessQuery.access_recordings_for(recording)
                                                .order(created_at: :asc, id: :asc)
                                                .filter_map do |access_recording|
      actor = access_recording.recordable&.actor
      next unless actor

      {
        id: access_recording.id,
        actor_id: actor.id,
        direct_role: access_recording.recordable.role.to_s,
        effective_role: RecordingStudioAccessible.role_for(actor: actor, recording: recording)
      }
    end
  end

  def reference_inherited_rows(recording)
    direct_keys = reference_direct_rows(recording).to_set { |row| row[:actor_id] }
    rows = {}
    ancestor_recordings(recording).each do |ancestor|
      RecordingStudioAccessible::DirectAccessQuery.access_recordings_for(ancestor)
                                                  .order(created_at: :asc, id: :asc)
                                                  .each do |access_recording|
        actor = access_recording.recordable&.actor
        next unless actor
        next if direct_keys.include?(actor.id) || rows.key?(actor.id)

        effective_role = RecordingStudioAccessible.role_for(actor: actor, recording: recording)
        next unless effective_role

        rows[actor.id] = {
          actor_id: actor.id,
          source_id: ancestor.id,
          source_role: access_recording.recordable.role.to_s,
          effective_role: effective_role
        }
      end
    end
    rows.values
  end

  def ancestor_recordings(recording)
    ancestors = []
    current = recording.parent_recording
    while current
      ancestors << current
      current = current.parent_recording
    end
    ancestors
  end

  def avatar_ids(view, recording, scope)
    view.send(:recording_studio_accessible_access_holders, recording, scope: scope).map(&:id)
  end

  def reference_avatar_ids(recording, scope)
    recordings = scope.to_s == "direct" ? [recording] : [recording] + ancestor_recordings(recording)
    seen = {}
    recordings.flat_map do |current|
      relation = RecordingStudioAccessible::DirectAccessQuery.access_recordings_for(current)
      relation = relation.order(created_at: :asc, id: :asc)
      relation.filter_map do |access_recording|
        actor = access_recording.recordable&.actor
        next unless actor
        next if seen[actor.id]

        seen[actor.id] = true
        actor.id
      end
    end
  end

  def grant_dependent(actor:, role:, parent:, manager:)
    RecordingStudioAccessible::AccessCreationContext.allow do
      RecordingStudio.root_recording_or_self(parent).record(
        RecordingStudio::Access,
        parent_recording: parent
      ) do |access|
        access.actor = actor
        access.role = role
        access.depends_on_recording_id = manager.id
      end
    end
  end

  def grant_queries(queries)
    queries.select { |event| event[:sql].include?("parent_recording_id") && event[:sql].include?("recordable_type") }
  end

  def actor_queries(queries, table)
    queries.select { |event| event[:sql].include?("FROM \"#{table}\"") && event[:cached] != true }
  end

  def sql_queries
    queries = []
    callback = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      next if payload[:name] == "SCHEMA"
      next if sql.match?(/\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE|SET |SHOW )/i)

      queries << payload
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries
  end

  def assert_same_role(expected, actual, message = nil)
    if expected.nil?
      assert_nil actual, message
    else
      assert_equal expected, actual, message
    end
  end

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end
end
