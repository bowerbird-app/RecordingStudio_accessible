# frozen_string_literal: true

require_relative "../test_helper"

class RootRecordingEffectiveIdsParityTest < ActiveSupport::TestCase
  KIT = :"parity.kit_download"

  setup do
    @admin = create_user("parity-admin@example.com")
    @holder = create_user("parity-holder@example.com")
    @member = create_user("parity-member@example.com")
    @stranger = create_user("parity-stranger@example.com")

    _workspace, @allow, = open_root("Parity allow")
    grant(@member, :view, @allow)

    _workspace, @admin_root, = open_root("Parity admin floor")
    grant(@member, :admin, @admin_root)

    _workspace, @view_floor, = open_root("Parity view floor")
    grant(@member, :view, @view_floor)

    _workspace, @dependent_ok, admin_grant = open_root("Parity dependent ok")
    holder_grant = grant(@holder, :edit, @dependent_ok, depends_on: admin_grant)
    grant(@member, :view, @dependent_ok, depends_on: holder_grant)

    _workspace, @trashed_manager, admin_grant = open_root("Parity trashed manager")
    holder_grant = grant(@holder, :edit, @trashed_manager, depends_on: admin_grant)
    grant(@member, :view, @trashed_manager, depends_on: holder_grant)
    holder_grant.update_column(:trashed_at, Time.current)

    _workspace, @weak_manager, admin_grant = open_root("Parity weak manager")
    holder_grant = grant(@holder, :edit, @weak_manager, depends_on: admin_grant)
    grant(@member, :edit, @weak_manager, depends_on: holder_grant)
    store_role!(holder_grant, :view)

    _workspace, @chain, admin_grant = open_root("Parity chain")
    holder_grant = grant(@holder, :edit, @chain, depends_on: admin_grant)
    grant(@member, :view, @chain, depends_on: holder_grant)

    @cycle, cycle_left, cycle_right = cycle_pair
    point_at!(cycle_left, cycle_right.id)
    point_at!(cycle_right, cycle_left.id)

    _workspace, @self_depend, = open_root("Parity self")
    self_grant = grant(@member, :view, @self_depend)
    point_at!(self_grant, self_grant.id)

    _workspace, @missing_manager, = open_root("Parity missing manager")
    missing = grant(@member, :view, @missing_manager)
    point_at!(missing, SecureRandom.uuid)

    _workspace, @not_access, = open_root("Parity not access")
    not_access = grant(@member, :view, @not_access)
    point_at!(not_access, @not_access.id)

    _workspace, @off_root, = open_root("Parity off root")
    _other_workspace, other_root, other_admin = open_root("Parity other root")
    other_holder = grant(@holder, :admin, other_root, depends_on: other_admin)
    off_root = grant(@member, :view, @off_root)
    point_at!(off_root, other_holder.id)

    _workspace, @destroyed_manager, admin_grant = open_root("Parity destroyed manager")
    holder_grant = grant(@holder, :edit, @destroyed_manager, depends_on: admin_grant)
    grant(@member, :view, @destroyed_manager, depends_on: holder_grant)
    RecordingStudio::Event.where(recording_id: holder_grant.id).delete_all
    holder_grant.delete

    _workspace, @trashed_grant, = open_root("Parity trashed grant")
    trashed_grant = grant(@member, :view, @trashed_grant)
    trashed_grant.update_column(:trashed_at, Time.current)

    _workspace, @trashed_root, = open_root("Parity trashed root")
    grant(@member, :view, @trashed_root)
    @trashed_root.update_column(:trashed_at, Time.current)

    child_workspace, @child_root, = open_root("Parity child")
    folder = Folder.create!(workspace: child_workspace, name: "Child", summary: "Folder", position: 1)
    child = create_child_recording(recordable: folder, parent_recording: @child_root)
    grant(@member, :edit, child)

    _workspace, @unranked_independent, = open_root("Parity unranked independent")
    unranked = grant(@member, :view, @unranked_independent)
    store_role!(unranked, "download")

    _workspace, @unranked_dependent, admin_grant = open_root("Parity unranked dependent")
    unranked_dependent = grant(@member, :view, @unranked_dependent, depends_on: admin_grant)
    store_role!(unranked_dependent, "download")

    audience_workspace, @audience, = open_root("Parity audience")
    grant(@member, :view, @audience)
    @audience_folder = Folder.create!(workspace: audience_workspace, name: "Kits", summary: "Kits", position: 0)
    @audience_folder_recording = create_child_recording(recordable: @audience_folder, parent_recording: @audience)

    @shared = shared_message_root
    group = MessageGroup.create!(message_root: @shared_recordable, name: "Group", summary: "Group", position: 0)
    @group = create_child_recording(recordable: group, parent_recording: @shared)
    owner = RecordingStudioAccessible.bootstrap_owner_access!(recording: @group, actor: @admin)
    assert owner.success?, owner.error.to_s
    grant(@member, :view, @group)
  end

  test "sql root ids match the ruby effective grant filter" do
    assert_equal legacy_ids(@member), listed_ids(@member)
    assert_equal legacy_ids(@member), listed_recording_ids(@member)
    assert_equal legacy_ids(@member, minimum_role: :view), listed_ids(@member, minimum_role: :view)
    assert_equal legacy_ids(@member, minimum_role: :edit), listed_ids(@member, minimum_role: :edit)
    assert_equal legacy_ids(@member, minimum_role: :admin), listed_ids(@member, minimum_role: :admin)
    assert_equal legacy_ids(@member, minimum_role: ""), listed_ids(@member, minimum_role: "")
    assert_equal legacy_ids(@member, minimum_role: :download), listed_ids(@member, minimum_role: :download)
    assert_equal legacy_ids(@stranger), listed_ids(@stranger)
    assert_equal legacy_ids(@admin, minimum_role: :admin), listed_ids(@admin, minimum_role: :admin)
  end

  test "allow deny dependent trash and shared roots keep the same membership" do
    ids = listed_ids(@member)

    assert_includes ids, @allow.id
    assert_includes ids, @admin_root.id
    assert_includes ids, @view_floor.id
    assert_includes ids, @dependent_ok.id
    assert_includes ids, @chain.id
    assert_includes ids, @child_root.id
    assert_includes ids, @trashed_root.id
    assert_includes ids, @unranked_independent.id
    assert_includes ids, @audience.id

    refute_includes ids, @trashed_manager.id
    refute_includes ids, @weak_manager.id
    refute_includes ids, @cycle.id
    refute_includes ids, @self_depend.id
    refute_includes ids, @missing_manager.id
    refute_includes ids, @not_access.id
    refute_includes ids, @off_root.id
    refute_includes ids, @destroyed_manager.id
    refute_includes ids, @trashed_grant.id
    refute_includes ids, @unranked_dependent.id
    refute_includes ids, @shared.id
    assert_equal ids.uniq, ids

    assert_equal [ @admin_root.id ], listed_ids(@member, minimum_role: :admin)
    assert_includes listed_ids(@member, minimum_role: :edit), @child_root.id
    refute_includes listed_ids(@member, minimum_role: :edit), @view_floor.id
    refute_includes listed_ids(@member, minimum_role: :view), @unranked_independent.id
    assert_empty listed_ids(@stranger)
    assert_empty listed_ids(@member, minimum_role: :download)

    assert RecordingStudioAccessible.authorized?(actor: @member, recording: @allow, role: :view)
    assert RecordingStudioAccessible.authorized?(actor: @member, recording: @dependent_ok, role: :view)
    assert RecordingStudioAccessible.authorized?(actor: @member, recording: @chain, role: :view)
    refute RecordingStudioAccessible.authorized?(actor: @member, recording: @chain, role: :edit)
    assert RecordingStudioAccessible.authorized?(actor: @member, recording: @group, role: :view)
    refute RecordingStudioAccessible.authorized?(actor: @member, recording: @trashed_manager, role: :view)
    refute RecordingStudioAccessible.authorized?(actor: @member, recording: @weak_manager, role: :view)
    refute RecordingStudioAccessible.authorized?(actor: @member, recording: @cycle, role: :view)
    refute RecordingStudioAccessible.authorized?(actor: @stranger, recording: @allow, role: :view)
  end

  test "narrowing an audience does not change the root set" do
    before = listed_ids(@member)
    configure_kit
    RecordingStudioAccessible.set_audience!(
      recording: @audience_folder_recording,
      action: KIT,
      audience: :public,
      actor: @admin
    )
    RecordingStudioAccessible.set_audience_constraint!(
      root: @audience,
      action: KIT,
      allowed_audiences: %i[granted],
      actor: @admin
    )

    assert_equal :granted, RecordingStudioAccessible.effective_audience(recording: @audience_folder_recording, action: KIT)
    assert_equal before, listed_ids(@member)
    assert_equal legacy_ids(@member), listed_ids(@member)
    assert_includes listed_ids(@member), @audience.id
    assert RecordingStudioAccessible.authorized?(actor: @member, recording: @audience, role: :view)
  ensure
    restore_audiences
  end

  test "dependent roots stay in one distinct subquery" do
    insert_repeated_grants(@allow, 4)
    relation = RecordingStudioAccessible::AuthorizationService.send(
      :root_recordings_relation_for, actor: @member, minimum_role: nil
    )
    sql = relation.to_sql

    assert_includes sql, "WITH RECURSIVE"
    assert_includes sql, "DISTINCT"
    assert_operator sql.scan(@allow.id).size, :<=, 1
    assert_equal legacy_ids(@member), listed_ids(@member)

    count = sql_count { listed_ids(@member) }
    assert_operator count, :<=, 3
  end

  private

  def listed_ids(actor, minimum_role: nil)
    RecordingStudioAccessible.root_recording_ids_for(actor: actor, minimum_role: minimum_role).sort
  end

  def listed_recording_ids(actor, minimum_role: nil)
    RecordingStudioAccessible.root_recordings_for(actor: actor, minimum_role: minimum_role).map(&:id).sort
  end

  # Previous root-list filter: load the actor's grants and keep a root when
  # DependentAccess.effective? says the grant still holds.
  def legacy_ids(actor, minimum_role: nil)
    service = RecordingStudioAccessible::AuthorizationService
    root_access = service.send(:root_access_recordings_for, actor: actor, minimum_role: minimum_role)
    return [] unless root_access.exists?

    ids = root_access.includes(:recordable).filter_map do |access_recording|
      access_recording.root_recording_id if RecordingStudioAccessible::DependentAccess.effective?(access_recording)
    end
    relation = RecordingStudio::Recording.unscoped.where(id: ids).distinct
    service.send(:exclude_shared_roots, relation).pluck(:id).sort
  end

  def open_root(name)
    workspace = Workspace.create!(name: name)
    recording = create_root_recording(workspace)
    admin_grant = RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: @admin)
    assert admin_grant.success?, admin_grant.error.to_s
    [ workspace, recording, admin_grant.value ]
  end

  def grant(actor, role, recording, depends_on: nil)
    result = RecordingStudioAccessible.grant_access(
      recording: recording,
      actor: actor,
      role: role,
      manager_actor: @admin,
      depends_on: depends_on
    )
    assert result.success?, "#{actor.id} #{role} #{recording.id}: #{result.error}"
    result.value
  end

  def cycle_pair
    workspace, recording, = open_root("Parity cycle")
    left_folder = Folder.create!(workspace: workspace, name: "Left", summary: "Left", position: 1)
    right_folder = Folder.create!(workspace: workspace, name: "Right", summary: "Right", position: 2)
    left = create_child_recording(recordable: left_folder, parent_recording: recording)
    right = create_child_recording(recordable: right_folder, parent_recording: recording)
    [ recording, grant(@member, :view, left), grant(@member, :view, right) ]
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

  def shared_message_root
    @shared_recordable = MessageRoot.create!(name: "Parity messages")
    create_root_recording(@shared_recordable)
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

  def insert_repeated_grants(root, count)
    connection = ActiveRecord::Base.connection
    now = Time.current
    count.times do
      access_id = SecureRandom.uuid
      connection.exec_insert(<<~SQL.squish, "SQL", [])
        INSERT INTO recording_studio_accesses
          (id, actor_type, actor_id, role, created_at)
        VALUES
          (#{connection.quote(access_id)}, #{connection.quote(RecordingStudioAccessible::ActorType.for(@member))},
           #{connection.quote(@member.id)}, 'view', #{connection.quote(now)})
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

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end
end
