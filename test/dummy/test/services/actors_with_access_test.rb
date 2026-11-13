# frozen_string_literal: true

require "test_helper"
require "recording_studio_accessible/api"

class ActorsWithAccessTest < ActiveSupport::TestCase
  AccessGrant = Struct.new(:actor)
  Context = Struct.new(:recording, :access_grant, :params, keyword_init: true)

  setup do
    @admin = create_user("actors-admin@example.com")
    @editor = create_user("actors-editor@example.com")
    @viewer = create_user("actors-viewer@example.com")
    @root_only = create_user("actors-root-only@example.com")
    @gone = create_user("actors-gone@example.com")
    @trashed_actor = create_user("actors-trashed@example.com")
    @mistyped = create_user("actors-mistyped@example.com")
    @workspace = Workspace.create!(name: "Actors With Access")
    @workspace_actor = Workspace.create!(name: "Actors Workspace Member")
    @root = create_root_recording(@workspace)
    folder = Folder.create!(workspace: @workspace, name: "Actors Folder", summary: "Folder", position: 0)
    @folder = create_child_recording(recordable: folder, parent_recording: @root)
    page = Page.create!(folder: folder, title: "Actors Page", summary: "Page", position: 0)
    @page = create_child_recording(recordable: page, parent_recording: @folder)

    create_direct_access_recording(actor: @admin, role: :admin, parent_recording: @root)
    create_direct_access_recording(actor: @admin, role: :view, parent_recording: @folder)
    create_direct_access_recording(actor: @editor, role: :edit, parent_recording: @folder)
    create_direct_access_recording(actor: @viewer, role: :view, parent_recording: @folder)
    create_direct_access_recording(actor: @root_only, role: :edit, parent_recording: @root)
    create_direct_access_recording(actor: @workspace_actor, role: :edit, parent_recording: @root)
    create_direct_access_recording(actor: @gone, role: :admin, parent_recording: @folder)
    trashed = create_direct_access_recording(actor: @trashed_actor, role: :admin, parent_recording: @folder)
    trashed.update_column(:trashed_at, Time.current)
    mistyped = create_direct_access_recording(actor: @mistyped, role: :admin, parent_recording: @folder)
    RecordingStudio::Access.where(id: mistyped.recordable_id).update_all(actor_type: "MissingActorType")
    @gone.delete

    invite = RecordingStudioAccessible.invite_access(
      recording: @folder,
      email: "actors-pending@example.com",
      role: :admin,
      manager_actor: @admin
    )
    assert invite.success?, invite.error.to_s
  end

  test "lists the strongest effective role for each actor on the path" do
    entries = RecordingStudioAccessible.actors_with_access(recording: @page)

    assert_equal(
      {
        @admin => :admin,
        @editor => :edit,
        @viewer => :view,
        @root_only => :edit,
        @workspace_actor => :edit
      },
      entries.to_h { |entry| [entry.actor, entry.role] }
    )
    assert_kind_of RecordingStudioAccessible::ActorAccess, entries.first
    entries.each do |entry|
      assert_equal entry.role, RecordingStudioAccessible.role_for(actor: entry.actor, recording: @page)
    end
    keys = entries.map { |entry| [entry.actor.class.base_class.name, entry.actor.id.to_s] }
    assert_equal keys.sort, keys
  end

  test "minimum_role keeps actors whose effective role is high enough" do
    editors = RecordingStudioAccessible.actors_with_access(recording: @page, minimum_role: :edit)
    admins = RecordingStudioAccessible.actors_with_access(recording: @page, minimum_role: :admin)

    assert_equal [@admin, @editor, @root_only, @workspace_actor].map(&:id).sort, editors.map { |entry| entry.actor.id }.sort
    assert_equal [:edit, :edit, :edit, :admin].tally, editors.map(&:role).tally
    refute_includes editors.map(&:actor), @viewer
    assert_equal [[@admin, :admin]], admins.map { |entry| [entry.actor, entry.role] }
    assert_empty RecordingStudioAccessible.actors_with_access(recording: @page, minimum_role: :download)
    assert_empty RecordingStudioAccessible.actors_with_access(recording: nil)
  end

  test "skips trashed grants, missing actors, invitations, and a type that does not load" do
    actors = RecordingStudioAccessible.actors_with_access(recording: @page).map(&:actor)

    refute_includes actors, @trashed_actor
    refute_includes actors, @mistyped
    refute_includes actors.map { |actor| actor.try(:email) }, "actors-pending@example.com"
    assert RecordingStudioAccessible::AccessInvitation.exists?(email: "actors-pending@example.com")
    refute RecordingStudioAccessible.authorized?(actor: @trashed_actor, recording: @page, role: :view)
  end

  test "reads kept grants once for the whole path and loads each actor type once" do
    queries = sql_queries do
      RecordingStudioAccessible.actors_with_access(recording: @page)
    end

    grant_queries = queries.select { |event| event[:sql].include?("parent_recording_id") && event[:sql].include?("recordable_type") }
    access_loads = queries.select { |event| event[:sql].include?("recording_studio_accesses") }
    user_loads = queries.select { |event| event[:sql].include?("FROM \"users\"") }
    workspace_loads = queries.select { |event| event[:sql].include?("FROM \"workspaces\"") }
    binds = Array(grant_queries.first && grant_queries.first[:type_casted_binds]).map(&:to_s)

    assert_equal 1, grant_queries.size
    assert_includes binds, @page.id
    assert_includes binds, @folder.id
    assert_includes binds, @root.id
    assert_equal 1, access_loads.size
    assert_equal 1, user_loads.size
    assert_equal 1, workspace_loads.size
    assert_match(/ IN \(/, user_loads.first[:sql])
    refute queries.any? { |event| event[:sql].include?("recording_studio_access_invitations") }
    refute queries.any? { |event| event[:sql].include?("recording_studio_access_rules") }
  end

  test "omits an ineffective direct dependent and still shows an inherited effective grant" do
    blocked = create_user("actors-blocked@example.com")
    covered = create_user("actors-covered@example.com")
    holder = create_user("actors-manager@example.com")
    manager = create_direct_access_recording(actor: holder, role: :admin, parent_recording: @folder)
    grant_dependent(actor: blocked, role: :view, parent: @folder, manager: manager)
    grant_dependent(actor: covered, role: :view, parent: @folder, manager: manager)
    create_direct_access_recording(actor: covered, role: :view, parent_recording: @root)
    manager.update_column(:trashed_at, Time.current)

    entries = RecordingStudioAccessible.actors_with_access(recording: @page)
    assert_nil entries.find { |entry| entry.actor == blocked }
    assert_equal :view, entries.find { |entry| entry.actor == covered }.role
    assert_equal :view, RecordingStudioAccessible.role_for(actor: covered, recording: @page)
    assert_nil RecordingStudioAccessible.role_for(actor: blocked, recording: @page)

    rows = RecordingStudioAccessible::AccessGrantList.rows_for(@folder)
    assert_nil rows.find { |row| row.actor == blocked }
    covered_rows = rows.select { |row| row.actor == covered }
    assert_equal [true], covered_rows.map(&:inherited)
    assert_equal ["view"], covered_rows.map { |row| row.role.to_s }
    assert_equal [:view], covered_rows.map(&:effective_role)
    assert_equal [@root.id], covered_rows.map { |row| row.source_recording.id }
    assert_nil covered_rows.first.access_recording

    viewer_row = rows.find { |row| row.actor == @viewer }
    refute viewer_row.inherited
    assert_equal "view", viewer_row.role.to_s
    assert_equal :view, viewer_row.effective_role
    assert_equal @folder.id, viewer_row.source_recording.id
    assert_equal @folder.id, viewer_row.access_recording.parent_recording_id

    admin_row = rows.find { |row| row.actor == @admin && !row.inherited }
    assert_equal "view", admin_row.role.to_s
    assert_equal :admin, admin_row.effective_role

    listed = RecordingStudioAccessible::Api::ListAccess.call(admin_context(@folder))
    granted = listed.fetch(:grants).select { |row| row.fetch(:status) == "granted" }
    pending = listed.fetch(:grants).select { |row| row.fetch(:status) == "pending" }
    assert_equal ["actors-pending@example.com"], pending.map { |row| row.fetch(:email) }
    refute granted.any? { |row| row.dig(:actor, :id) == blocked.id }
    covered_grant = granted.find { |row| row.dig(:actor, :id) == covered.id }
    assert covered_grant.fetch(:inherited)
    assert_equal "view", covered_grant.fetch(:role)
    assert_equal "view", covered_grant.fetch(:effective_role)
    assert_equal @root.id, covered_grant.fetch(:source_recording).fetch(:id)

    empty_root = create_root_recording(Workspace.create!(name: "Actors Empty Root"))
    refute RecordingStudioAccessible::LastAdminGuard.administered?(empty_root)
    assert RecordingStudioAccessible::LastAdminGuard.administered?(@page)
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def admin_context(recording)
    Context.new(recording: recording, access_grant: AccessGrant.new(@admin), params: {})
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
end
