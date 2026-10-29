require_relative "../test_helper"

class RecordingsForTest < ActiveSupport::TestCase
  setup do
    @user = create_user("recordings-for-user@example.com")
    @holder = create_user("recordings-for-holder@example.com")
    @manager = create_user("recordings-for-manager@example.com")

    @workspace = Workspace.create!(name: "Recordings For Workspace")
    @root = create_root_recording(@workspace)
    create_direct_access_recording(actor: @manager, role: :admin, parent_recording: @root)

    @folder = Folder.create!(workspace: @workspace, name: "Folder", summary: "Folder", position: 0)
    @folder_recording = create_child_recording(recordable: @folder, parent_recording: @root)

    @page = Page.create!(folder: @folder, title: "Page", summary: "Page", position: 0)
    @page_recording = create_child_recording(recordable: @page, parent_recording: @folder_recording)
    @other_page = Page.create!(folder: @folder, title: "Other", summary: "Other", position: 1)
    @other_page_recording = create_child_recording(recordable: @other_page, parent_recording: @folder_recording)
  end

  teardown do
    if Folder.instance_variable_defined?(:@accessible_role_set)
      Folder.remove_instance_variable(:@accessible_role_set)
    end
  end

  test "a direct grant on a child includes that child" do
    grant_access(@user, :view, @folder_recording)
    other = add_folder("Other folder")

    assert_equal [@folder_recording.id], listed_ids(parent: @root)
    refute_includes listed_ids(parent: @root), other.id
    assert_kind_of ActiveRecord::Relation, listed(parent: @root)
  end

  test "a grant on an ancestor includes a child with no grant of its own" do
    grant_access(@user, :view, @root)

    assert_empty RecordingStudioAccessible.access_recordings_for(@page_recording)
    assert_includes listed_ids(parent: @folder_recording), @page_recording.id
    assert_includes listed_ids(parent: @folder_recording), @other_page_recording.id
  end

  test "no grant returns an empty relation and no ids" do
    assert_empty listed(parent: @root)
    assert_equal [], listed_ids(parent: @root)
    assert_equal [], RecordingStudioAccessible.recording_ids_for(actor: @user, parent_recording: @root)
  end

  test "a child below the floor is omitted and a child at or above it is included" do
    grant_access(@user, :view, @folder_recording)
    editor_folder = add_folder("Editor folder")
    grant_access(@user, :edit, editor_folder)

    edit_ids = listed_ids(parent: @root, minimum_role: :edit)
    view_ids = listed_ids(parent: @root, minimum_role: :view)

    assert_includes edit_ids, editor_folder.id
    refute_includes edit_ids, @folder_recording.id
    assert_includes view_ids, editor_folder.id
    assert_includes view_ids, @folder_recording.id
  end

  test "parent admin and a child view grant still passes edit" do
    grant_access(@user, :admin, @root)
    grant_access(@user, :view, @folder_recording)

    assert_includes listed_ids(parent: @root, minimum_role: :edit), @folder_recording.id
    assert RecordingStudioAccessible.authorized?(actor: @user, recording: @folder_recording, role: :edit)
  end

  test "a child edit grant passes edit when the parent grant is only view" do
    grant_access(@user, :view, @root)
    grant_access(@user, :edit, @folder_recording)
    viewer_only = add_folder("Viewer only")

    edit_ids = listed_ids(parent: @root, minimum_role: :edit)

    assert_includes edit_ids, @folder_recording.id
    refute_includes edit_ids, viewer_only.id
  end

  test "a shared root parent lists authorized message groups" do
    root_recording, group_recording, other_group_recording = message_groups

    grant_access(@user, :view, group_recording)

    ids = listed_ids(parent: root_recording, recordable_type: "MessageGroup")

    assert_equal [group_recording.id], ids
  end

  test "a voided dependent grant excludes the child" do
    manager_grant = RecordingStudioAccessible.grant_access(
      recording: @folder_recording,
      actor: @holder,
      role: :edit,
      manager_actor: @manager
    ).value
    dependent = RecordingStudioAccessible.grant_access(
      recording: @folder_recording,
      actor: @user,
      role: :view,
      manager_actor: @manager,
      depends_on: manager_grant
    )
    assert dependent.success?, dependent.error
    assert_includes listed_ids(parent: @folder_recording), @page_recording.id

    manager_grant.update_column(:trashed_at, Time.current)

    refute_includes listed_ids(parent: @folder_recording), @page_recording.id
    assert_nil RecordingStudioAccessible.role_for(actor: @user, recording: @page_recording)
  end

  test "a trashed child is excluded while authorized? on that child stays true" do
    grant_access(@user, :view, @folder_recording)
    @page_recording.update_column(:trashed_at, Time.current)

    assert RecordingStudioAccessible.authorized?(actor: @user, recording: @page_recording, role: :view)
    refute_includes listed_ids(parent: @folder_recording), @page_recording.id
    assert_includes listed_ids(parent: @folder_recording), @other_page_recording.id
  end

  test "a trashed access grant does not include the child" do
    grant = grant_access(@user, :view, @folder_recording)
    assert_includes listed_ids(parent: @root), @folder_recording.id

    grant.update_column(:trashed_at, Time.current)

    refute_includes listed_ids(parent: @root), @folder_recording.id
    refute RecordingStudioAccessible.authorized?(actor: @user, recording: @folder_recording, role: :view)
  end

  test "recordable type string and class agree and a symbol array or blank string is empty" do
    root_recording, group_recording, other_group_recording = message_groups
    access_recording = insert_access_recording(actor: @user, role: :view, parent_recording: root_recording)

    string_ids = listed_ids(parent: root_recording, recordable_type: "MessageGroup").sort
    class_ids = listed_ids(parent: root_recording, recordable_type: MessageGroup).sort

    assert_equal [group_recording.id, other_group_recording.id].sort, string_ids
    assert_equal string_ids, class_ids
    refute_includes string_ids, access_recording.id

    untyped = listed_ids(parent: root_recording)
    assert_includes untyped, access_recording.id
    assert_includes untyped, group_recording.id

    assert_empty listed(parent: root_recording, recordable_type: :MessageGroup)
    assert_empty listed(parent: root_recording, recordable_type: ["MessageGroup"])
    assert_empty listed(parent: root_recording, recordable_type: "")
  end

  test "a blank floor keeps an effective unranked grant" do
    Folder.accessible_roles :view, :download
    grant_access(@user, :view, @folder_recording)
    download_folder = add_folder("Downloads")
    grant_access(@user, :download, download_folder)

    assert_nil RecordingStudioAccessible.role_for(actor: @user, recording: download_folder)
    assert RecordingStudioAccessible.authorized_for_role?(
      actor: @user, recording: download_folder, role: :download
    )

    assert_includes listed_ids(parent: @root), download_folder.id
    assert_includes listed_ids(parent: @root, minimum_role: ""), download_folder.id
    assert_includes listed_ids(parent: @root, minimum_role: false), download_folder.id
    assert_includes RecordingStudioAccessible.recording_ids_for(actor: @user, parent_recording: @root),
                    download_folder.id

    refute_includes listed_ids(parent: @root, minimum_role: :view), download_folder.id
    assert_includes listed_ids(parent: @root, minimum_role: :view), @folder_recording.id

    assert_ranked_parity(@root, :view)
    assert_ranked_parity(@folder_recording, :view)
    assert_blank_floor_parity(@root)
    assert_blank_floor_parity(@folder_recording)
  end

  test "a blank floor inherits an unranked ancestor grant" do
    Folder.accessible_roles :view, :download
    grant_access(@user, :download, @root)
    child = add_folder("Inherited download")

    assert_includes listed_ids(parent: @root), child.id
    refute_includes listed_ids(parent: @root, minimum_role: :view), child.id
  end

  test "an unranked minimum role returns an empty relation" do
    grant_access(@user, :view, @folder_recording)

    refute_empty listed(parent: @root, minimum_role: :view)
    assert_empty listed(parent: @root, minimum_role: :download)
    assert_empty listed(parent: @root, minimum_role: "VIEW")
    assert_equal [], RecordingStudioAccessible.recording_ids_for(
      actor: @user, parent_recording: @root, minimum_role: :download
    )
  end

  test "a missing actor parent or id returns an empty relation and no ids" do
    assert_empty listed(actor: nil, parent: @root)
    assert_equal [], RecordingStudioAccessible.recording_ids_for(actor: nil, parent_recording: @root)
    assert_empty listed(parent: nil)
    assert_empty listed(parent: RecordingStudio::Recording.new)
    assert_empty listed(parent: @workspace)
    assert_equal [], RecordingStudioAccessible.recording_ids_for(
      actor: @user, parent_recording: RecordingStudio::Recording.new
    )
  end

  test "recording ids match recordings_for pluck" do
    grant_access(@user, :view, @root)

    assert_equal listed(parent: @folder_recording).pluck(:id), listed_ids(parent: @folder_recording)
    assert_equal(
      listed(parent: @root, minimum_role: :view, recordable_type: "Folder").pluck(:id),
      RecordingStudioAccessible.recording_ids_for(
        actor: @user,
        parent_recording: @root,
        minimum_role: :view,
        recordable_type: "Folder"
      )
    )
  end

  test "a grant on a grandchild does not include the child" do
    insert_access_recording(actor: @user, role: :view, parent_recording: @page_recording)

    assert RecordingStudioAccessible.authorized?(actor: @user, recording: @page_recording, role: :view)
    refute_includes listed_ids(parent: @root), @folder_recording.id
    refute RecordingStudioAccessible.authorized?(actor: @user, recording: @folder_recording, role: :view)
  end

  test "order and limit stay inside the authorized ids" do
    grant_access(@user, :view, @root)
    full = listed_ids(parent: @folder_recording)
    limited = listed(parent: @folder_recording).order(:id).limit(1).pluck(:id)

    assert_equal 1, limited.length
    assert_includes full, limited.first
  end

  test "a child created after the call stays out of that relation" do
    grant_access(@user, :view, @root)
    relation = listed(parent: @folder_recording)
    extra = Page.create!(folder: @folder, title: "Later", summary: "Later", position: 2)
    extra_recording = create_child_recording(recordable: extra, parent_recording: @folder_recording)

    refute_includes relation.pluck(:id), extra_recording.id
    assert_includes listed_ids(parent: @folder_recording), extra_recording.id
  end

  test "a subclass actor is included through the stored base actor type" do
    actor_class = define_actor_subclass("RecordingsForSpecialUser")
    special = actor_class.create!(
      email: "recordings-for-special@example.com",
      password: "Password",
      password_confirmation: "Password"
    )
    grant_access(special, :view, @folder_recording)

    assert_includes listed_ids(actor: special, parent: @root), @folder_recording.id
  ensure
    remove_actor_subclass("RecordingsForSpecialUser")
  end

  private

  def listed(actor: @user, parent:, minimum_role: nil, recordable_type: nil)
    RecordingStudioAccessible.recordings_for(
      actor: actor,
      parent_recording: parent,
      minimum_role: minimum_role,
      recordable_type: recordable_type
    )
  end

  def listed_ids(...)
    listed(...).pluck(:id)
  end

  def grant_access(actor, role, parent_recording)
    create_direct_access_recording(actor: actor, role: role, parent_recording: parent_recording)
  end

  def add_folder(name)
    folder = Folder.create!(workspace: @workspace, name: name, summary: name, position: 1)
    create_child_recording(recordable: folder, parent_recording: @root)
  end

  def message_groups
    message_root = MessageRoot.create!(name: "Recordings For Messages")
    root_recording = create_root_recording(message_root)
    group = MessageGroup.create!(
      message_root: message_root, name: "Kept group", summary: "Kept", position: 0
    )
    other = MessageGroup.create!(
      message_root: message_root, name: "Other group", summary: "Other", position: 1
    )
    [
      root_recording,
      create_child_recording(recordable: group, parent_recording: root_recording),
      create_child_recording(recordable: other, parent_recording: root_recording)
    ]
  end

  def insert_access_recording(actor:, role:, parent_recording:)
    connection = ActiveRecord::Base.connection
    access_id = SecureRandom.uuid
    recording_id = SecureRandom.uuid
    now = Time.current.utc.iso8601(6)
    root_id = parent_recording.root_recording_id.presence || parent_recording.id
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
        (#{connection.quote(recording_id)}, 'RecordingStudio::Access', #{connection.quote(access_id)},
         #{connection.quote(parent_recording.id)}, #{connection.quote(root_id)},
         #{connection.quote(now)}, #{connection.quote(now)})
    SQL
    RecordingStudio::Recording.unscoped.find(recording_id)
  end

  def kept_direct_children(parent)
    RecordingStudio::Recording.where(parent_recording_id: parent.id).to_a
  end

  def assert_ranked_parity(parent, minimum_role)
    expected = kept_direct_children(parent).select { |child|
      RecordingStudioAccessible.authorized?(actor: @user, recording: child, role: minimum_role)
    }.map(&:id).sort
    assert_equal expected, listed_ids(parent: parent, minimum_role: minimum_role).sort
  end

  def assert_blank_floor_parity(parent)
    expected = kept_direct_children(parent).select { |child|
      RecordingStudioAccessible.authorized_for_any_role?(
        actor: @user,
        recording: child,
        roles: [:view, :edit, :admin, :download]
      )
    }.map(&:id).sort
    assert_equal expected, listed_ids(parent: parent).sort
  end

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def define_actor_subclass(name)
    remove_actor_subclass(name)
    Object.const_set(name, Class.new(User))
  end

  def remove_actor_subclass(name)
    Object.send(:remove_const, name) if Object.const_defined?(name, false)
  end
end
