# frozen_string_literal: true

require_relative "../test_helper"

class AuthorizedRecordingsParityTest < ActiveSupport::TestCase
  setup do
    @actor_types = RecordingStudioAccessible.configuration.access_actor_types
    RecordingStudioAccessible.configuration.access_actor_types = [ "User" ]

    @admin = create_user("recordings-admin@example.com")
    @member = create_user("recordings-member@example.com")
    @partial = create_user("recordings-partial@example.com")
    @broad = create_user("recordings-broad@example.com")
    @chain = create_user("recordings-chain@example.com")
    @blocked = create_user("recordings-blocked@example.com")

    build_root_tree
    build_child_trees
    build_dependent_tree
    build_stored_root_tree
  end

  teardown do
    RecordingStudioAccessible.configuration.access_actor_types = @actor_types
  end

  test "a root grant matches within, authorized_recording_ids, and authorized?" do
    page = recordings(actor: @member, root: @root)
    ids = page.pluck(:id)

    assert_equal RecordingStudio::Recording.within(@root).order(:id).pluck(:id), ids.sort
    assert_equal authorized_ids(@member, @root), ids.sort
    assert_parity(@member, @root, ids)
    sql = page.to_sql
    assert_includes sql, "root_recording_id"
    refute_includes sql, "WITH RECURSIVE"
    refute_predicate page, :loaded?
  end

  test "a narrow child grant matches authorized_recording_ids and does not paste seed ids" do
    page = recordings(actor: @partial, root: @child_root)
    ids = page.pluck(:id)

    assert_equal authorized_ids(@partial, @child_root), ids.sort
    assert_includes ids, @narrow_folder.id
    assert_includes ids, @narrow_page.id
    refute_includes ids, @broad_folder.id
    refute_includes ids, @child_root.id
    assert_parity(@partial, @child_root, ids)

    sql = page.to_sql
    assert_includes sql, "recording_studio_accesses"
    assert_includes sql, "OFFSET 0"
    refute_includes sql, @narrow_folder.id
    refute_includes sql, @narrow_page.id
    refute_predicate page, :loaded?
  end

  test "a broad child grant matches authorized_recording_ids" do
    ids = recordings(actor: @broad, root: @child_root).pluck(:id)

    assert_equal authorized_ids(@broad, @child_root), ids.sort
    assert_includes ids, @broad_folder.id
    assert_includes ids, @broad_page.id
    assert_includes ids, @broad_nested.id
    refute_includes ids, @narrow_folder.id
    refute_includes ids, @child_root.id
    assert_parity(@broad, @child_root, ids)
  end

  test "a stored root matches authorized_recording_ids" do
    page = recordings(actor: @member, root: @stored_root)
    ids = page.pluck(:id)

    assert_equal authorized_ids(@member, @stored_root), ids.sort
    assert_includes ids, @stored_child.id
    refute_includes ids, @plain_child.id
    refute_includes ids, @stored_root.id
    assert_parity(@member, @stored_root, ids)
    assert_includes page.to_sql, "root_covered"
  end

  test "a dependent grant matches authorized_recording_ids and a weak manager stays out" do
    ids = recordings(actor: @chain, root: @dependent_root).pluck(:id)

    assert_equal authorized_ids(@chain, @dependent_root), ids.sort
    assert_includes ids, @chain_folder.id
    assert_parity(@chain, @dependent_root, ids)
    assert_empty recordings(actor: @blocked, root: @dependent_root).pluck(:id)
    assert_empty authorized_ids(@blocked, @dependent_root)
  end

  test "nil actor, a bad role, and recordable_type follow authorized_recording_ids" do
    empty = recordings(actor: nil, root: @root)
    assert_equal RecordingStudio::Recording.none.to_sql, empty.to_sql
    assert_empty empty

    assert_equal RecordingStudio::Recording.none.to_sql, recordings(actor: @member, root: @root, role: :download).to_sql
    assert_equal RecordingStudio::Recording.none.to_sql, recordings(actor: @member, root: "root").to_sql
    assert_equal RecordingStudio::Recording.none.to_sql,
                 recordings(actor: @member, root: @root, recordable_type: "").to_sql

    pages = recordings(actor: @member, root: @root, recordable_type: "Page").pluck(:id)
    assert_equal authorized_ids(@member, @root, recordable_type: "Page"), pages.sort
    assert_includes pages, @root_page.id
    refute_includes pages, @root_folder.id
    assert_equal pages.sort, recordings(actor: @member, root: @root, recordable_type: Page).pluck(:id).sort

    scoped = recordings(actor: @member, root: @root, scope: RecordingStudio::Recording.where(recordable_type: "Page"))
    assert_equal pages.sort, scoped.pluck(:id).sort
  end

  test "a limited order is the same page as authorized_recording_ids" do
    [ [ @member, @root ], [ @partial, @child_root ], [ @broad, @child_root ], [ @member, @stored_root ] ].each do |actor, root|
      expected = RecordingStudio::Recording.where(id: id_relation(actor, root))
                                           .order(created_at: :desc, id: :desc)
                                           .limit(2)
                                           .pluck(:id)
      actual = recordings(actor: actor, root: root).order(created_at: :desc, id: :desc).limit(2).pluck(:id)
      assert_equal expected, actual
    end
  end

  private

  def recordings(actor:, root:, scope: RecordingStudio::Recording.all, role: :view, recordable_type: nil)
    RecordingStudioAccessible.authorized_recordings(
      actor: actor,
      root: root,
      scope: scope,
      role: role,
      recordable_type: recordable_type
    )
  end

  def id_relation(actor, root, recordable_type: nil)
    RecordingStudioAccessible.authorized_recording_ids(
      actor: actor,
      root: root,
      role: :view,
      recordable_type: recordable_type
    )
  end

  def authorized_ids(actor, root, recordable_type: nil)
    id_relation(actor, root, recordable_type: recordable_type).pluck(:id).sort
  end

  def assert_parity(actor, root, ids)
    tree_for(root).each do |recording|
      allowed = RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: :view)
      assert_equal allowed, ids.include?(recording.id), "#{recording.id} authorized=#{allowed}"
    end
  end

  def build_root_tree
    workspace, root = owned("Recordings root")
    @root = root
    folder = Folder.create!(workspace: workspace, name: "Root folder", summary: "Folder", position: 1)
    @root_folder = create_child_recording(recordable: folder, parent_recording: root)
    @root_page = add_page(folder, @root_folder, "Root page")
    grant(@member, :view, root)
  end

  def build_child_trees
    workspace, root = owned("Recordings children")
    @child_root = root
    @narrow_folder = add_folder(workspace, root, "Narrow")
    @narrow_page = add_page(@narrow_folder.recordable, @narrow_folder, "Narrow page")
    @broad_folder = add_folder(workspace, root, "Broad")
    @broad_page = add_page(@broad_folder.recordable, @broad_folder, "Broad page")
    card = Card.create!(page: @broad_page.recordable, title: "Broad card", body: "Card", position: 1)
    @broad_nested = create_child_recording(recordable: card, parent_recording: @broad_page)
    grant(@partial, :view, @narrow_folder)
    grant(@broad, :view, @broad_folder)
  end

  def build_dependent_tree
    workspace, root = owned("Recordings dependent")
    @dependent_root = root
    @chain_folder = add_folder(workspace, root, "Chain")
    holder = grant(@admin, :edit, @chain_folder)
    grant(@chain, :view, @chain_folder, depends_on: holder)
    weak_folder = add_folder(workspace, root, "Weak")
    weak = grant(@admin, :edit, weak_folder)
    grant(@blocked, :edit, weak_folder, depends_on: weak)
    store_role!(weak, :view)
  end

  def build_stored_root_tree
    _workspace, source = owned("Recordings stored source")
    grant(@member, :view, source)
    workspace, root = owned("Recordings stored tree")
    @stored_root = root
    @stored_child = add_folder(workspace, root, "Stores source")
    @plain_child = add_folder(workspace, root, "Plain")
    @stored_child.update_column(:root_recording_id, source.id)
  end

  def owned(name)
    workspace = Workspace.create!(name: name)
    recording = create_root_recording(workspace)
    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: @admin)
    assert result.success?, result.error.to_s
    [ workspace, recording ]
  end

  def add_folder(workspace, parent, name)
    folder = Folder.create!(workspace: workspace, name: name, summary: name, position: 1)
    create_child_recording(recordable: folder, parent_recording: parent)
  end

  def add_page(folder, folder_recording, title)
    page = Page.create!(folder: folder, title: title, summary: title, position: 1)
    create_child_recording(recordable: page, parent_recording: folder_recording)
  end

  def grant(actor, role, recording, depends_on: nil)
    result = RecordingStudioAccessible.grant_access(
      recording: recording,
      actor: actor,
      role: role,
      manager_actor: @admin,
      depends_on: depends_on
    )
    assert result.success?, result.error.to_s
    result.value
  end

  def store_role!(access_recording, role)
    connection = ActiveRecord::Base.connection
    connection.execute(<<~SQL.squish)
      UPDATE recording_studio_accesses
      SET role = #{connection.quote(role.to_s)}
      WHERE id = #{connection.quote(access_recording.recordable_id)}
    SQL
  end

  def tree_for(root)
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

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end
end
