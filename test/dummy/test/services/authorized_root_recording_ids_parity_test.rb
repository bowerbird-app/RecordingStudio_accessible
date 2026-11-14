# frozen_string_literal: true

require_relative "../test_helper"

class AuthorizedRootRecordingIdsParityTest < ActiveSupport::TestCase
  KIT = :"parity.roots.kit_download"

  setup do
    @actor_types = RecordingStudioAccessible.configuration.access_actor_types
    RecordingStudioAccessible.configuration.access_actor_types = [ "User", "Workspace" ]

    @admin = create_user("root-ids-admin@example.com")
    @holder = create_user("root-ids-holder@example.com")
    @member = create_user("root-ids-member@example.com")
    @stranger = create_user("root-ids-stranger@example.com")
    @workspace = Workspace.create!(name: "Root ids actor")
    @catalog = []

    @view_root = owned_root("view", "Root ids view")
    @view_grant = grant(@member, :view, @view_root)
    assert_equal @view_root.id, @view_grant.parent_recording_id
    assert_equal @view_grant.parent_recording_id, @view_grant.root_recording_id

    @edit_root = owned_root("edit", "Root ids edit")
    grant(@member, :edit, @edit_root)

    @admin_root = owned_root("admin", "Root ids admin")
    grant(@member, :admin, @admin_root)

    @dependent_root = owned_root("dependent", "Root ids dependent")
    holder_grant = grant(@holder, :edit, @dependent_root, depends_on: admin_grant_for(@dependent_root))
    grant(@member, :view, @dependent_root, depends_on: holder_grant)

    @equal_root = owned_root("equal dependent", "Root ids equal")
    holder_grant = grant(@holder, :edit, @equal_root, depends_on: admin_grant_for(@equal_root))
    grant(@member, :edit, @equal_root, depends_on: holder_grant)

    @trashed_manager_root = owned_root("trashed manager", "Root ids trashed manager")
    holder_grant = grant(@holder, :edit, @trashed_manager_root, depends_on: admin_grant_for(@trashed_manager_root))
    grant(@member, :view, @trashed_manager_root, depends_on: holder_grant)
    holder_grant.update_column(:trashed_at, Time.current)

    @weak_root = owned_root("weaker manager", "Root ids weak")
    holder_grant = grant(@holder, :edit, @weak_root, depends_on: admin_grant_for(@weak_root))
    grant(@member, :edit, @weak_root, depends_on: holder_grant)
    store_role!(holder_grant, :view)

    @cycle_root = owned_root("cycle", "Root ids cycle")
    left = grant(@member, :view, @cycle_root)
    right = grant(@holder, :view, @cycle_root)
    point_at!(left, right.id)
    point_at!(right, left.id)

    @self_root = owned_root("self cycle", "Root ids self")
    self_grant = grant(@member, :view, @self_root)
    point_at!(self_grant, self_grant.id)

    @missing_root = owned_root("missing manager", "Root ids missing")
    missing = grant(@member, :view, @missing_root)
    point_at!(missing, SecureRandom.uuid)

    @not_access_root = owned_root("manager not access", "Root ids not access")
    not_access = grant(@member, :view, @not_access_root)
    point_at!(not_access, @not_access_root.id)

    @off_root = owned_root("off root", "Root ids off root")
    _other_workspace, other_root = open_root("Root ids other")
    track("other", other_root)
    other_holder = grant(@holder, :admin, other_root, depends_on: admin_grant_for(other_root))
    off_root = grant(@member, :view, @off_root)
    point_at!(off_root, other_holder.id)

    @destroyed_root = owned_root("destroyed manager", "Root ids destroyed")
    holder_grant = grant(@holder, :edit, @destroyed_root, depends_on: admin_grant_for(@destroyed_root))
    grant(@member, :view, @destroyed_root, depends_on: holder_grant)
    RecordingStudio::Event.where(recording_id: holder_grant.id).delete_all
    holder_grant.delete

    @trashed_grant_root = owned_root("trashed grant", "Root ids trashed grant")
    trashed_grant = grant(@member, :view, @trashed_grant_root)
    trashed_grant.update_column(:trashed_at, Time.current)

    @trashed_root = owned_root("trashed root", "Root ids trashed root")
    grant(@member, :view, @trashed_root)
    @trashed_root.update_column(:trashed_at, Time.current)

    child_workspace, @child_root = open_root("Root ids child")
    track("child only", @child_root)
    folder = Folder.create!(workspace: child_workspace, name: "Child", summary: "Folder", position: 1)
    @child = create_child_recording(recordable: folder, parent_recording: @child_root)
    grant(@member, :edit, @child)

    @unranked_root = owned_root("unranked", "Root ids unranked")
    unranked = grant(@member, :view, @unranked_root)
    store_role!(unranked, "download")

    @unranked_dependent_root = owned_root("unranked dependent", "Root ids unranked dependent")
    unranked_dependent = grant(
      @member,
      :view,
      @unranked_dependent_root,
      depends_on: admin_grant_for(@unranked_dependent_root)
    )
    store_role!(unranked_dependent, "download")

    @audience_root = owned_root("audience", "Root ids audience")
    grant(@member, :view, @audience_root)

    @workspace_root = owned_root("workspace actor", "Root ids workspace actor")
    grant(@workspace, :edit, @workspace_root)

    @shared_child = track("shared child", shared_message_root("Root ids shared child"))
    group = MessageGroup.create!(message_root: @shared_child_recordable, name: "Group", summary: "Group", position: 0)
    @group = create_child_recording(recordable: group, parent_recording: @shared_child)
    owner = RecordingStudioAccessible.bootstrap_owner_access!(recording: @group, actor: @admin)
    assert owner.success?, owner.error.to_s
    grant(@member, :view, @group)

    @shared_grant = track("shared grant", shared_message_root("Root ids shared grant"))
    insert_root_grant(@member, :view, @shared_grant)
  end

  teardown do
    RecordingStudioAccessible.configuration.access_actor_types = @actor_types
    restore_audiences
  end

  test "relation membership matches authorized? for every actor, root, and role" do
    mismatches = []

    actors.each do |actor|
      roles.each do |role|
        ids = authorized_ids(actor, role)
        @catalog.each do |name, root|
          allowed = RecordingStudioAccessible.authorized?(actor: actor, recording: root, role: role)
          next if allowed == ids.include?(root.id)

          mismatches << "#{actor_label(actor)} #{name} #{role.inspect} authorized=#{allowed}"
        end
      end
    end

    assert_empty mismatches
    assert_equal authorized_ids(@member, :view).sort, authorized_ids(@member, "view").sort
  end

  test "child grants stay out and a legacy shared-root grant stays in" do
    assert RecordingStudioAccessible.authorized?(actor: @member, recording: @child, role: :edit)
    refute RecordingStudioAccessible.authorized?(actor: @member, recording: @child_root, role: :edit)
    refute_includes authorized_ids(@member, :edit), @child_root.id
    assert_includes RecordingStudioAccessible.root_recording_ids_for(actor: @member, minimum_role: :edit), @child_root.id

    assert RecordingStudioAccessible.authorized?(actor: @member, recording: @group, role: :view)
    refute_includes authorized_ids(@member, :view), @shared_child.id
    refute_includes RecordingStudioAccessible.root_recording_ids_for(actor: @member), @shared_child.id

    assert RecordingStudioAccessible.authorized?(actor: @member, recording: @shared_grant, role: :view)
    assert_includes authorized_ids(@member, :view), @shared_grant.id
    refute_includes RecordingStudioAccessible.root_recording_ids_for(actor: @member), @shared_grant.id
    refute_includes authorized_ids(@workspace, :view), @view_root.id
    assert_includes authorized_ids(@workspace, :edit), @workspace_root.id
    refute_includes authorized_ids(@workspace, :admin), @workspace_root.id
  end

  test "a root audience limit does not change authorized roots" do
    before = authorized_ids(@member, :view)
    configure_kit
    RecordingStudioAccessible.set_audience!(
      recording: @audience_root,
      action: KIT,
      audience: :public,
      actor: @admin
    )
    RecordingStudioAccessible.set_audience_constraint!(
      root: @audience_root,
      action: KIT,
      allowed_audiences: %i[granted],
      actor: @admin
    )

    assert_equal :granted, RecordingStudioAccessible.effective_audience(recording: @audience_root, action: KIT)
    assert_equal before, authorized_ids(@member, :view)
    assert_includes authorized_ids(@member, :view), @audience_root.id
    assert RecordingStudioAccessible.authorized?(actor: @member, recording: @audience_root, role: :view)
  end

  test "nil actor and an invalid role are an empty recording relation" do
    [ nil, :download, "", "VIEW" ].each do |role|
      relation = RecordingStudioAccessible.authorized_root_recording_ids(actor: @member, role: role)
      assert_equal RecordingStudio::Recording.none.to_sql, relation.to_sql
      assert_empty RecordingStudio::Recording.where(id: relation)
      @catalog.each do |name, root|
        refute RecordingStudioAccessible.authorized?(actor: @member, recording: root, role: role), name
      end
    end

    empty = RecordingStudioAccessible.authorized_root_recording_ids(actor: nil, role: :view)
    assert_equal RecordingStudio::Recording.none.to_sql, empty.to_sql
    assert_empty RecordingStudio::Recording.where(id: empty)
  end

  test "query count stays constant and the relation composes inside where" do
    authorized_ids(@member, :view)
    before = uncached_sql_count { authorized_ids(@member, :view) }
    insert_repeated_grants(@view_root, 40)
    after = uncached_sql_count { authorized_ids(@member, :view) }

    assert_equal before, after
    assert_equal 1, before

    relation = RecordingStudioAccessible.authorized_root_recording_ids(actor: @member, role: :view)
    composed = RecordingStudio::Recording.where(id: relation).pluck(:id).sort
    assert_equal relation.pluck(:id).sort, composed
    assert_includes composed, @view_root.id
    refute_includes composed, @child_root.id
  end

  private

  def actors
    [ nil, @member, @admin, @holder, @stranger, @workspace ]
  end

  def roles
    [ :view, :edit, :admin ]
  end

  def authorized_ids(actor, role)
    RecordingStudioAccessible.authorized_root_recording_ids(actor: actor, role: role).pluck(:id)
  end

  def owned_root(label, name)
    _workspace, recording = open_root(name)
    track(label, recording)
  end

  def track(name, recording)
    @catalog << [ name, recording ]
    recording
  end

  def open_root(name)
    workspace = Workspace.create!(name: name)
    recording = create_root_recording(workspace)
    admin_grant = RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: @admin)
    assert admin_grant.success?, admin_grant.error.to_s
    [ workspace, recording ]
  end

  def admin_grant_for(root)
    grant = RecordingStudioAccessible.access_recordings_for_actor(recording: root, actor: @admin).first
    assert grant, "missing admin grant on #{root.id}"
    grant
  end

  def grant(actor, role, recording, depends_on: nil)
    result = RecordingStudioAccessible.grant_access(
      recording: recording,
      actor: actor,
      role: role,
      manager_actor: @admin,
      depends_on: depends_on
    )
    assert result.success?, "#{actor.class} #{role} #{recording.id}: #{result.error}"
    result.value
  end

  def point_at!(access_recording, manager_id)
    connection = ActiveRecord::Base.connection
    connection.execute(<<~SQL.squish)
      UPDATE recording_studio_accesses
      SET depends_on_recording_id = #{connection.quote(manager_id)}
      WHERE id = #{connection.quote(access_recording.recordable_id)}
    SQL
  end

  def store_role!(access_recording, role)
    connection = ActiveRecord::Base.connection
    connection.execute(<<~SQL.squish)
      UPDATE recording_studio_accesses
      SET role = #{connection.quote(role.to_s)}
      WHERE id = #{connection.quote(access_recording.recordable_id)}
    SQL
  end

  def shared_message_root(name)
    recordable = MessageRoot.create!(name: name)
    @shared_child_recordable = recordable if name.include?("child")
    create_root_recording(recordable)
  end

  def insert_root_grant(actor, role, root)
    connection = ActiveRecord::Base.connection
    now = Time.current
    access_id = SecureRandom.uuid
    connection.exec_insert(<<~SQL.squish, "SQL", [])
      INSERT INTO recording_studio_accesses
        (id, actor_type, actor_id, role, created_at)
      VALUES
        (#{connection.quote(access_id)}, #{connection.quote(RecordingStudioAccessible::ActorType.for(actor))},
         #{connection.quote(actor.id)}, #{connection.quote(role.to_s)}, #{connection.quote(now)})
    SQL
    connection.exec_insert(<<~SQL.squish, "SQL", [])
      INSERT INTO recording_studio_recordings
        (id, recordable_type, recordable_id, parent_recording_id, root_recording_id, created_at, updated_at)
      VALUES
        (#{connection.quote(SecureRandom.uuid)}, 'RecordingStudio::Access', #{connection.quote(access_id)},
         #{connection.quote(root.id)}, #{connection.quote(root.id)},
         #{connection.quote(now)}, #{connection.quote(now)})
    SQL
  end

  def insert_repeated_grants(root, count)
    count.times { insert_root_grant(@member, :view, root) }
  end

  def configure_kit
    @original_action_audiences = RecordingStudioAccessible.configuration.action_audiences.to_h
    RecordingStudioAccessible.configuration.action_audiences[KIT] = {
      allowed: %i[public signed_in granted],
      default: :public,
      granted_roles: %i[view edit admin],
      granted_override: false,
      manage_role: :admin
    }
  end

  def restore_audiences
    return unless defined?(@original_action_audiences) && @original_action_audiences

    RecordingStudioAccessible.configuration.action_audiences.replace(@original_action_audiences)
  end

  def uncached_sql_count
    count = nil
    ActiveRecord::Base.uncached { count = sql_count { yield } }
    count
  end

  def sql_count
    count = 0
    callback = lambda do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      next if payload[:cached] || payload[:name] == "SCHEMA" || sql.include?("SCHEMA")

      count += 1
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    count
  end

  def actor_label(actor)
    return "nil" unless actor

    "#{actor.class.name}:#{actor.try(:email) || actor.try(:name)}"
  end

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end
end
