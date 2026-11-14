# frozen_string_literal: true

require_relative "../test_helper"

class AuthorizedRecordingIdsParityTest < ActiveSupport::TestCase
  KIT = :"parity.recordings.kit_download"

  setup do
    @actor_types = RecordingStudioAccessible.configuration.access_actor_types
    RecordingStudioAccessible.configuration.access_actor_types = [ "User", "Workspace" ]

    @admin = create_user("recording-ids-admin@example.com")
    @holder = create_user("recording-ids-holder@example.com")
    @member = create_user("recording-ids-member@example.com")
    @stranger = create_user("recording-ids-stranger@example.com")
    @workspace = Workspace.create!(name: "Recording ids actor")
    @scenarios = []
    @names = {}

    build_inherited_tree
    build_child_only_tree
    build_stronger_ancestor_tree
    build_effective_dependent_tree
    build_voided_trees
    build_trashed_trees
    build_shared_trees
    build_off_path_tree
    build_workspace_actor_tree
    _, @audience_root = owned("audience", "Recording ids audience")
    grant(@member, :view, @audience_root)
  end

  teardown do
    RecordingStudioAccessible.configuration.access_actor_types = @actor_types
    restore_audiences
  end

  test "relation membership matches authorized? for every recording in each tree" do
    mismatches = []

    actors.each do |actor|
      roles.each do |role|
        @scenarios.each do |root|
          ids = authorized_ids(actor, root, role)
          tree = tree_for(root)
          (ids - tree.map(&:id)).each do |id|
            mismatches << "#{label(actor, root, role)} extra #{id}"
          end
          tree.each do |recording|
            allowed = RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: role)
            next if allowed == ids.include?(recording.id)

            mismatches << "#{label(actor, root, role)} #{recording.recordable_type}:#{recording.id} " \
                          "authorized=#{allowed} trashed=#{recording.trashed_at.present?}"
          end
        end
      end
    end

    assert_empty mismatches
    assert_equal authorized_ids(@member, @inherited, :view).sort, authorized_ids(@member, @inherited, "view").sort
  end

  test "recordable type keeps inheritance and drops other types" do
    pages = authorized_ids(@member, @inherited, :edit, recordable_type: "Page")
    expected = tree_for(@inherited).select { |recording|
      recording.recordable_type == "Page" &&
        RecordingStudioAccessible.authorized?(actor: @member, recording: recording, role: :edit)
    }.map(&:id)

    assert_equal expected.sort, pages.sort
    assert_includes pages, @page.id
    refute_includes pages, @sibling_page.id
    refute_includes pages, @inherited_folder.id
    assert_equal pages.sort, authorized_ids(@member, @inherited, :edit, recordable_type: Page).sort

    view_pages = authorized_ids(@member, @inherited, :view, recordable_type: "Page")
    assert_includes view_pages, @page.id
    assert_includes view_pages, @sibling_page.id

    assert_empty authorized_ids(@member, @inherited, :view, recordable_type: "NoSuchType")
    assert_equal RecordingStudio::Recording.none.to_sql,
                 relation(actor: @member, root: @inherited, recordable_type: "").to_sql
    assert_equal RecordingStudio::Recording.none.to_sql,
                 relation(actor: @member, root: @inherited, recordable_type: 1).to_sql
  end

  test "nil actor, a non-recording root, and an invalid role are an empty relation" do
    [ nil, :download, "", "VIEW" ].each do |role|
      built = relation(actor: @member, root: @inherited, role: role)
      assert_equal RecordingStudio::Recording.none.to_sql, built.to_sql
      assert_empty RecordingStudio::Recording.where(id: built)
    end

    [ nil, @member, "root" ].each do |root|
      built = relation(actor: @member, root: root, role: :view)
      next if root.equal?(@inherited)

      assert_equal RecordingStudio::Recording.none.to_sql, built.to_sql
    end

    empty = relation(actor: nil, root: @inherited, role: :view)
    assert_equal RecordingStudio::Recording.none.to_sql, empty.to_sql
    assert_empty RecordingStudio::Recording.where(id: empty)
  end

  test "the relation stays unloaded and composes inside one where query" do
    built = relation(actor: @member, root: @inherited, role: :view)
    refute_predicate built, :loaded?
    sql = built.to_sql
    assert_includes sql, "WITH RECURSIVE"
    assert_includes sql, "parent_recording_id"
    refute_includes sql, @page.id
    refute_includes sql, @inherited_folder.id

    composed = RecordingStudio::Recording.where(id: built).limit(2)
    assert_includes composed.to_sql, "WITH RECURSIVE"
    refute_includes composed.to_sql, @page.id

    ids = nil
    assert_equal 0, uncached_sql_count { built.to_sql }
    assert_equal 1, uncached_sql_count { ids = composed.pluck(:id) }
    assert_operator ids.length, :<=, 2
    refute_predicate built, :loaded?

    full = authorized_ids(@member, @inherited, :view)
    assert_operator full.length, :>, 2
    assert_empty ids - full
  end

  test "adding recordings does not add queries or interpolate their ids" do
    built = relation(actor: @member, root: @inherited, role: :view)
    built.pluck(:id)
    before = uncached_sql_count { built.pluck(:id) }
    inserted = insert_child(parent: @inherited, root: @inherited, recordable: @page)
    fresh = nil
    after = uncached_sql_count { fresh = relation(actor: @member, root: @inherited, role: :view).pluck(:id) }

    assert_equal 1, before
    assert_equal before, after
    assert_includes fresh, inserted
    loaded = RecordingStudio::Recording.unscoped.find(inserted)
    assert RecordingStudioAccessible.authorized?(actor: @member, recording: loaded, role: :view)
    refute_includes relation(actor: @member, root: @inherited, role: :view).to_sql, inserted
  end

  test "a root audience limit does not change authorized recordings" do
    before = {}
    actors.each do |actor|
      roles.each do |role|
        before[[ actor, role ]] = membership(@audience_root, actor, role)
      end
    end

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
    actors.each do |actor|
      roles.each do |role|
        assert_equal before[[ actor, role ]], membership(@audience_root, actor, role), label(actor, @audience_root, role)
      end
    end
    rule = RecordingStudioAccessible::AudienceQuery.rule_recording_for(recording: @audience_root, action: KIT)
    assert_includes authorized_ids(@member, @audience_root, :view), rule.id
    assert RecordingStudioAccessible.authorized?(actor: @member, recording: rule, role: :view)
    refute_includes authorized_ids(@stranger, @audience_root, :view), @audience_root.id
    refute_includes authorized_ids(@stranger, @audience_root, :view), rule.id
    refute RecordingStudioAccessible.authorized?(actor: @stranger, recording: rule, role: :view)
  end

  private

  def actors
    [ nil, @member, @admin, @holder, @stranger, @workspace ]
  end

  def roles
    [ :view, :edit, :admin ]
  end

  def build_inherited_tree
    workspace, root = owned("inherited", "Recording ids inherited")
    @inherited = root
    folder = Folder.create!(workspace: workspace, name: "Inherited folder", summary: "Folder", position: 1)
    @inherited_folder = create_child_recording(recordable: folder, parent_recording: root)
    @page = add_page(folder, @inherited_folder, "Inherited page")
    sibling = Folder.create!(workspace: workspace, name: "Inherited sibling", summary: "Sibling", position: 2)
    @sibling = create_child_recording(recordable: sibling, parent_recording: root)
    @sibling_page = add_page(sibling, @sibling, "Sibling page")
    grant(@member, :view, root)
    grant(@member, :edit, @inherited_folder)
    watch("folder param", @inherited_folder)
  end

  def build_child_only_tree
    workspace, root = owned("child only", "Recording ids child only")
    folder = Folder.create!(workspace: workspace, name: "Child only folder", summary: "Folder", position: 1)
    folder_recording = create_child_recording(recordable: folder, parent_recording: root)
    add_page(folder, folder_recording, "Child only page")
    sibling = Folder.create!(workspace: workspace, name: "Child only sibling", summary: "Sibling", position: 2)
    create_child_recording(recordable: sibling, parent_recording: root)
    grant(@member, :edit, folder_recording)
  end

  def build_stronger_ancestor_tree
    workspace, root = owned("stronger ancestor", "Recording ids stronger")
    folder = Folder.create!(workspace: workspace, name: "Stronger folder", summary: "Folder", position: 1)
    folder_recording = create_child_recording(recordable: folder, parent_recording: root)
    add_page(folder, folder_recording, "Stronger page")
    grant(@member, :admin, root)
    grant(@member, :view, folder_recording)
  end

  def build_effective_dependent_tree
    workspace, root = owned("effective dependent", "Recording ids effective dependent")
    folder = Folder.create!(workspace: workspace, name: "Dependent folder", summary: "Folder", position: 1)
    folder_recording = create_child_recording(recordable: folder, parent_recording: root)
    add_page(folder, folder_recording, "Dependent page")
    holder_grant = grant(@holder, :edit, folder_recording, depends_on: admin_grant_for(root))
    grant(@member, :view, folder_recording, depends_on: holder_grant)
  end

  def build_voided_trees
    voided = owned("voided manager", "Recording ids voided").last
    holder_grant = grant(@holder, :edit, voided, depends_on: admin_grant_for(voided))
    grant(@member, :view, voided, depends_on: holder_grant)
    holder_grant.update_column(:trashed_at, Time.current)

    weaker = owned("weaker manager", "Recording ids weaker").last
    holder_grant = grant(@holder, :edit, weaker, depends_on: admin_grant_for(weaker))
    grant(@member, :edit, weaker, depends_on: holder_grant)
    store_role!(holder_grant, :view)

    cycle = owned("cycle", "Recording ids cycle").last
    left = grant(@member, :view, cycle)
    right = grant(@holder, :view, cycle)
    point_at!(left, right.id)
    point_at!(right, left.id)

    self_cycle = owned("self cycle", "Recording ids self").last
    self_grant = grant(@member, :view, self_cycle)
    point_at!(self_grant, self_grant.id)

    missing = owned("missing manager", "Recording ids missing").last
    missing_grant = grant(@member, :view, missing)
    point_at!(missing_grant, SecureRandom.uuid)

    _other_workspace, other = owned("manager elsewhere", "Recording ids elsewhere")
    other_holder = grant(@holder, :admin, other, depends_on: admin_grant_for(other))
    off_root = owned("off root manager", "Recording ids off root manager").last
    off_grant = grant(@member, :view, off_root)
    point_at!(off_grant, other_holder.id)

    destroyed = owned("destroyed manager", "Recording ids destroyed").last
    holder_grant = grant(@holder, :edit, destroyed, depends_on: admin_grant_for(destroyed))
    grant(@member, :view, destroyed, depends_on: holder_grant)
    RecordingStudio::Event.where(recording_id: holder_grant.id).delete_all
    holder_grant.delete

    unranked = owned("unranked", "Recording ids unranked").last
    unranked_grant = grant(@member, :view, unranked)
    store_role!(unranked_grant, "download")
  end

  def build_trashed_trees
    trashed_grant_root = owned("trashed grant", "Recording ids trashed grant").last
    trashed_grant = grant(@member, :view, trashed_grant_root)
    trashed_grant.update_column(:trashed_at, Time.current)

    workspace, root = owned("trashed recording", "Recording ids trashed recording")
    folder = Folder.create!(workspace: workspace, name: "Trashed folder", summary: "Folder", position: 1)
    folder_recording = create_child_recording(recordable: folder, parent_recording: root)
    add_page(folder, folder_recording, "Under trashed folder")
    grant(@member, :view, folder_recording)
    folder_recording.update_column(:trashed_at, Time.current)
  end

  def build_shared_trees
    shared_child = track("shared child", shared_message_root("Recording ids shared child"))
    group = MessageGroup.create!(message_root: shared_child.recordable, name: "Group", summary: "Group", position: 0)
    group_recording = create_child_recording(recordable: group, parent_recording: shared_child)
    owner = RecordingStudioAccessible.bootstrap_owner_access!(recording: group_recording, actor: @admin)
    assert owner.success?, owner.error.to_s
    grant(@member, :view, group_recording)

    shared_grant = track("shared grant", shared_message_root("Recording ids shared grant"))
    legacy_group = MessageGroup.create!(
      message_root: shared_grant.recordable, name: "Legacy", summary: "Legacy", position: 0
    )
    create_child_recording(recordable: legacy_group, parent_recording: shared_grant)
    insert_root_grant(@member, :view, shared_grant)
  end

  def build_off_path_tree
    _source_workspace, source = owned("off path source", "Recording ids off path source")
    grant(@member, :view, source)
    workspace, root = owned("off path tree", "Recording ids off path tree")
    folder = Folder.create!(workspace: workspace, name: "Off path folder", summary: "Folder", position: 1)
    folder_recording = create_child_recording(recordable: folder, parent_recording: root)
    add_page(folder, folder_recording, "Off path normal")
    shared_page = add_page(folder, folder_recording, "Off path shared root")
    folder_recording.update_column(:root_recording_id, source.id)
    shared_page.update_column(:root_recording_id, source.id)
  end

  def build_workspace_actor_tree
    root = owned("workspace actor", "Recording ids workspace actor").last
    grant(@workspace, :edit, root)
  end

  def owned(label, name)
    workspace = Workspace.create!(name: name)
    recording = create_root_recording(workspace)
    admin_grant = RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: @admin)
    assert admin_grant.success?, admin_grant.error.to_s
    watch(label, recording)
    [ workspace, recording ]
  end

  def watch(name, recording)
    @names[recording.id] = name
    @scenarios << recording
    recording
  end
  alias track watch

  def add_page(folder, folder_recording, title)
    page = Page.create!(folder: folder, title: title, summary: title, position: 1)
    create_child_recording(recordable: page, parent_recording: folder_recording)
  end

  def relation(actor:, root:, role: :view, recordable_type: nil)
    RecordingStudioAccessible.authorized_recording_ids(
      actor: actor,
      root: root,
      role: role,
      recordable_type: recordable_type
    )
  end

  def authorized_ids(actor, root, role, recordable_type: nil)
    relation(actor: actor, root: root, role: role, recordable_type: recordable_type).pluck(:id)
  end

  def membership(root, actor, role)
    ids = authorized_ids(actor, root, role)
    tree_for(root).to_h { |recording| [ recording.id, ids.include?(recording.id) ] }
  end

  def tree_for(root)
    @trees ||= {}
    @trees[root.id] ||= recordings_under(root)
  end

  def recordings_under(root)
    connection = ActiveRecord::Base.connection
    ids = connection.select_values(<<~SQL.squish)
      WITH RECURSIVE tree AS (
        SELECT id, ARRAY[id]::uuid[] AS seen
        FROM recording_studio_recordings
        WHERE id = #{connection.quote(root.id)}
        UNION ALL
        SELECT child.id, tree.seen || child.id
        FROM recording_studio_recordings child
        INNER JOIN tree ON child.parent_recording_id = tree.id
        WHERE NOT (child.id = ANY(tree.seen))
      )
      SELECT id FROM tree
    SQL
    RecordingStudio::Recording.unscoped.where(id: ids).to_a
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

  def admin_grant_for(root)
    found = RecordingStudioAccessible.access_recordings_for_actor(recording: root, actor: @admin).first
    assert found, "missing admin grant on #{root.id}"
    found
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
    create_root_recording(MessageRoot.create!(name: name))
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

  def insert_child(parent:, root:, recordable:)
    connection = ActiveRecord::Base.connection
    now = Time.current
    id = SecureRandom.uuid
    connection.exec_insert(<<~SQL.squish, "SQL", [])
      INSERT INTO recording_studio_recordings
        (id, recordable_type, recordable_id, parent_recording_id, root_recording_id, created_at, updated_at)
      VALUES
        (#{connection.quote(id)}, #{connection.quote(recordable.recordable_type)},
         #{connection.quote(recordable.recordable_id)},
         #{connection.quote(parent.id)}, #{connection.quote(root.id)},
         #{connection.quote(now)}, #{connection.quote(now)})
    SQL
    id
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

  def label(actor, root, role)
    "#{actor_label(actor)} #{@names[root.id]} #{role.inspect}"
  end

  def actor_label(actor)
    return "nil" unless actor

    "#{actor.class.name}:#{actor.try(:email) || actor.try(:name)}"
  end

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end
end
