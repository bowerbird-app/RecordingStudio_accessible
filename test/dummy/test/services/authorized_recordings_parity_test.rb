# frozen_string_literal: true

require_relative "../test_helper"
require "recording_studio/test_helpers"

class AuthorizedRecordingsParityTest < ActiveSupport::TestCase
  include RecordingStudio::TestHelpers
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
    build_nested_anchor_tree
    assert_root_invariant!
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
    page = recordings(actor: @member, root: @stored_source)
    ids = page.pluck(:id)

    assert_equal authorized_ids(@member, @stored_source), ids.sort
    assert_equal RecordingStudio::Recording.within(@stored_source).order(:id).pluck(:id), ids.sort
    assert_parity(@member, @stored_source, ids)
    assert_includes page.to_sql, "root_recording_id"
    refute_includes page.to_sql, "WITH RECURSIVE"

    other = recordings(actor: @member, root: @stored_root).pluck(:id)
    assert_empty other
    assert_empty authorized_ids(@member, @stored_root)
    refute_includes other, @stored_child.id
    refute_includes other, @plain_child.id
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

  test "a nested anchor matches authorized_recording_ids" do
    root_ids = recordings(actor: @nested_root_actor, root: @nested_anchor).pluck(:id)
    assert_equal authorized_ids(@nested_root_actor, @nested_anchor), root_ids.sort
    assert_includes root_ids, @nested_anchor.id
    assert_includes root_ids, @nested_inner.id
    assert_includes root_ids, @nested_inner_page.id
    assert_includes root_ids, @nested_other.id
    refute_includes root_ids, @nested_sibling.id
    refute_includes root_ids, @nested_workspace.id
    assert_parity(@nested_root_actor, @nested_anchor, root_ids)

    child_ids = recordings(actor: @nested_child_actor, root: @nested_anchor).pluck(:id)
    assert_equal authorized_ids(@nested_child_actor, @nested_anchor), child_ids.sort
    assert_includes child_ids, @nested_inner.id
    assert_includes child_ids, @nested_inner_page.id
    refute_includes child_ids, @nested_anchor.id
    refute_includes child_ids, @nested_other.id
    refute_includes child_ids, @nested_sibling.id
    assert_parity(@nested_child_actor, @nested_anchor, child_ids)

    outside_ids = recordings(actor: @nested_outside_actor, root: @nested_anchor).pluck(:id)
    assert_empty outside_ids
    assert_empty authorized_ids(@nested_outside_actor, @nested_anchor)
    assert_includes recordings(actor: @nested_outside_actor, root: @nested_sibling).pluck(:id), @nested_sibling.id
  end

  test "a broad nested anchor pages from the workspace root" do
    with_broad_threshold(0) do
      page = recordings(actor: @nested_root_actor, root: @nested_anchor)
      ids = page.pluck(:id)
      sql = page.to_sql

      assert_equal authorized_ids(@nested_root_actor, @nested_anchor), ids.sort
      assert_includes ids, @nested_inner_page.id
      refute_includes ids, @nested_sibling.id
      assert_includes sql, @nested_workspace.id
      assert_includes sql, "seed_ids"
      refute_includes sql, "OFFSET 0"
      refute_includes sql, "root_covered"

      expected = RecordingStudio::Recording.where(id: id_relation(@nested_root_actor, @nested_anchor))
                                           .order(created_at: :desc, id: :desc)
                                           .limit(2)
                                           .pluck(:id)
      actual = page.order(created_at: :desc, id: :desc).limit(2).pluck(:id)
      assert_equal expected, actual
    end
  end

  test "a parent cycle terminates and a root grant includes rows that claim that root" do
    _workspace, root = owned("Recordings parent cycle")
    sibling = add_folder(_workspace, root, "Outside cycle")
    left = add_folder(_workspace, root, "Cycle left")
    right = add_page(left.recordable, left, "Cycle right")
    child_actor = create_user("recordings-cycle-child@example.com")
    root_actor = create_user("recordings-cycle-root@example.com")
    grant(child_actor, :view, left)
    grant(root_actor, :view, root)

    connection = ActiveRecord::Base.connection
    connection.execute(<<~SQL.squish)
      UPDATE recording_studio_recordings
      SET parent_recording_id = #{connection.quote(right.id)}
      WHERE id = #{connection.quote(left.id)}
    SQL
    connection.execute("SET CONSTRAINTS fk_rs_recordings_on_parent_and_root IMMEDIATE")
    assert_root_invariant!

    child_ids = recordings(actor: child_actor, root: left).pluck(:id)
    assert_includes child_ids, left.id
    assert_includes child_ids, right.id
    refute_includes child_ids, sibling.id
    refute_includes child_ids, root.id
    assert_equal authorized_ids(child_actor, left), child_ids.sort

    from_root = recordings(actor: child_actor, root: root).pluck(:id)
    refute_includes from_root, left.id
    refute_includes from_root, right.id
    refute_includes from_root, sibling.id

    root_page = recordings(actor: root_actor, root: root)
    root_ids = root_page.pluck(:id)
    assert_includes root_ids, left.id
    assert_includes root_ids, right.id
    assert_includes root_ids, sibling.id
    assert_equal RecordingStudio::Recording.within(root).order(:id).pluck(:id), root_ids.sort
    assert_equal authorized_ids(root_actor, root), root_ids.sort
    refute_includes root_page.to_sql, "WITH RECURSIVE"
  end

  test "a limited order is the same page as authorized_recording_ids" do
    [ [ @member, @root ], [ @partial, @child_root ], [ @broad, @child_root ], [ @member, @stored_source ] ].each do |actor, root|
      expected = RecordingStudio::Recording.where(id: id_relation(actor, root))
                                           .order(created_at: :desc, id: :desc)
                                           .limit(2)
                                           .pluck(:id)
      actual = recordings(actor: actor, root: root).order(created_at: :desc, id: :desc).limit(2).pluck(:id)
      assert_equal expected, actual
    end
  end

  private

  def with_broad_threshold(limit)
    klass = RecordingStudioAccessible::AuthorizedRecordingIds
    previous = klass::BROAD_SUBTREE_ROWS
    klass.send(:remove_const, :BROAD_SUBTREE_ROWS)
    klass.const_set(:BROAD_SUBTREE_ROWS, limit)
    yield
  ensure
    klass.send(:remove_const, :BROAD_SUBTREE_ROWS)
    klass.const_set(:BROAD_SUBTREE_ROWS, previous)
  end

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
    @stored_source = source
    workspace, root = owned("Recordings stored tree")
    @stored_root = root
    @stored_child = add_folder(workspace, root, "Stores source")
    @plain_child = add_folder(workspace, root, "Plain")
  end

  def build_nested_anchor_tree
    workspace, root = owned("Recordings nested anchor")
    @nested_workspace = root
    @nested_anchor = add_folder(workspace, root, "Anchor")
    @nested_inner = add_folder(workspace, root, "Inner")
    @nested_inner_page = add_page(@nested_inner.recordable, @nested_inner, "Inner page")
    @nested_other = add_folder(workspace, root, "Other")
    @nested_sibling = add_folder(workspace, root, "Sibling of anchor")
    @nested_root_actor = create_user("recordings-nested-root@example.com")
    @nested_child_actor = create_user("recordings-nested-child@example.com")
    @nested_outside_actor = create_user("recordings-nested-outside@example.com")
    grant(@nested_root_actor, :view, root)
    grant(@nested_child_actor, :view, @nested_inner)
    grant(@nested_outside_actor, :view, @nested_sibling)
    @nested_inner.update_column(:parent_recording_id, @nested_anchor.id)
    @nested_other.update_column(:parent_recording_id, @nested_anchor.id)
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
