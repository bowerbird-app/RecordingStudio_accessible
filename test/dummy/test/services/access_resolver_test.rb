require_relative "../test_helper"

class AccessResolverTest < ActiveSupport::TestCase
  setup do
    @admin = create_user("resolver-admin@example.com")
    @editor = create_user("resolver-editor@example.com")
    @viewer = create_user("resolver-viewer@example.com")

    workspace = Workspace.create!(name: "Resolver Workspace")
    @root_recording = create_root_recording(workspace)

    folder = Folder.create!(workspace: workspace, name: "Resolver Folder", summary: "Folder", position: 0)
    @folder_recording = create_child_recording(recordable: folder, parent_recording: @root_recording)

    page = Page.create!(folder: folder, title: "Resolver Page", summary: "Page", position: 0)
    @page_recording = create_child_recording(recordable: page, parent_recording: @folder_recording)
  end

  test "returns direct access on the current recording before inherited access" do
    grant_access(@viewer, :view, @root_recording)
    grant_access(@viewer, :edit, @folder_recording, @root_recording)

    assert_equal :edit, RecordingStudioAccessible.role_for(actor: @viewer, recording: @folder_recording)
  end

  test "inherits root access on descendant recordings" do
    grant_access(@editor, :edit, @root_recording)

    assert_equal :edit, RecordingStudioAccessible.role_for(actor: @editor, recording: @page_recording)
    assert RecordingStudioAccessible.authorized?(actor: @editor, recording: @page_recording, role: :view)
  end

  test "root listing helpers remain aligned" do
    grant_access(@admin, :admin, @root_recording)

    expected_recordings = [@root_recording]
    expected_ids = expected_recordings.map(&:id)

    assert_equal expected_recordings, RecordingStudioAccessible.root_recordings_for(actor: @admin)
    assert_equal expected_ids, RecordingStudioAccessible.root_recording_ids_for(actor: @admin)
  end

  test "root listing helpers resolve descendant grants to their RecordingStudio root" do
    access_recording = grant_access(@admin, :admin, @folder_recording, @root_recording)

    assert_equal @root_recording.id, @root_recording.root_recording_id
    assert_equal @root_recording.id, @folder_recording.root_recording_id
    assert_equal @root_recording.id, access_recording.root_recording_id
    assert_equal [@root_recording], RecordingStudioAccessible.root_recordings_for(actor: @admin)
    assert_equal [@root_recording.id], RecordingStudioAccessible.root_recording_ids_for(actor: @admin)
  end

  test "subclass actors resolve through the stored base polymorphic type" do
    actor_class = define_actor_subclass("ResolverSpecialUser")
    special_user = actor_class.create!(
      email: "resolver-special@example.com",
      password: "Password",
      password_confirmation: "Password"
    )
    access_recording = grant_access(special_user, :view, @root_recording)

    assert_equal RecordingStudioAccessible::ActorType.for(special_user), access_recording.recordable.actor_type
    assert_equal :view, RecordingStudioAccessible.role_for(actor: special_user, recording: @root_recording)
    assert_equal [access_recording.id],
                 RecordingStudioAccessible::DirectAccessQuery.access_recordings_for_actor(
                    recording: @root_recording,
                    actor: special_user
                  ).pluck(:id)
    assert_equal [@root_recording.id],
                 RecordingStudioAccessible.root_recording_ids_for(actor: special_user)
  ensure
    remove_actor_subclass("ResolverSpecialUser")
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def grant_access(user, role, parent_recording, root_recording = parent_recording)
    create_direct_access_recording(actor: user, role: role, parent_recording: parent_recording)
  end

  def define_actor_subclass(name)
    remove_actor_subclass(name)
    Object.const_set(name, Class.new(User))
  end

  def remove_actor_subclass(name)
    Object.send(:remove_const, name) if Object.const_defined?(name, false)
  end
end
