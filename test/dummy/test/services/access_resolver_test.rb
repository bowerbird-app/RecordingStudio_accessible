require_relative "../test_helper"

class AccessResolverTest < ActiveSupport::TestCase
  setup do
    @admin = create_user("resolver-admin@example.com")
    @editor = create_user("resolver-editor@example.com")
    @viewer = create_user("resolver-viewer@example.com")

    workspace = Workspace.create!(name: "Resolver Workspace")
    @root_recording = RecordingStudio::Recording.unscoped.create!(recordable: workspace, parent_recording_id: nil)

    folder = Folder.create!(workspace: workspace, name: "Resolver Folder", summary: "Folder", position: 0)
    @folder_recording = RecordingStudio::Recording.unscoped.create!(
      recordable: folder,
      parent_recording_id: @root_recording.id,
      root_recording_id: @root_recording.id
    )

    page = Page.create!(folder: folder, title: "Resolver Page", summary: "Page", position: 0)
    @page_recording = RecordingStudio::Recording.unscoped.create!(
      recordable: page,
      parent_recording_id: @folder_recording.id,
      root_recording_id: @root_recording.id
    )
  end

  test "returns direct access on the current recording before inherited access" do
    grant_access(@viewer, :view, @root_recording)
    grant_access(@viewer, :edit, @folder_recording, @root_recording)

    assert_equal :edit, RecordingStudioAccessible.role_for(actor: @viewer, recording: @folder_recording)
  end

  test "inherits root access when no boundary exists on the path" do
    grant_access(@editor, :edit, @root_recording)

    assert_equal :edit, RecordingStudioAccessible.role_for(actor: @editor, recording: @page_recording)
    assert RecordingStudioAccessible.authorized?(actor: @editor, recording: @page_recording, role: :view)
  end

  test "boundary blocks weaker inherited access" do
    grant_access(@viewer, :view, @root_recording)
    create_boundary(parent_recording: @folder_recording, minimum_role: :edit)

    assert_nil RecordingStudioAccessible.role_for(actor: @viewer, recording: @page_recording)
    refute RecordingStudioAccessible.authorized?(actor: @viewer, recording: @page_recording, role: :view)
  end

  test "direct access inside a boundary overrides blocked inherited access" do
    grant_access(@viewer, :view, @root_recording)
    create_boundary(parent_recording: @folder_recording, minimum_role: :admin)
    grant_access(@viewer, :edit, @page_recording, @root_recording)

    assert_equal :edit, RecordingStudioAccessible::Authorization.role_for(actor: @viewer, recording: @page_recording)
    assert RecordingStudioAccessible::Authorization.allowed?(actor: @viewer, recording: @page_recording, role: :edit)
  end

  test "root listing helpers remain aligned" do
    grant_access(@admin, :admin, @root_recording)

    expected_recordings = [@root_recording]
    expected_ids = expected_recordings.map(&:id)

    assert_equal expected_recordings, RecordingStudioAccessible.root_recordings_for(actor: @admin)
    assert_equal expected_ids, RecordingStudioAccessible.root_recording_ids_for(actor: @admin)
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
    access = RecordingStudio::Access.create!(actor: user, role: role)
    RecordingStudio::Recording.unscoped.create!(
      root_recording_id: root_recording.id,
      parent_recording_id: parent_recording.id,
      recordable: access
    )
  end

  def create_boundary(parent_recording:, minimum_role:)
    boundary = RecordingStudio::AccessBoundary.create!(minimum_role: minimum_role)
    RecordingStudio::Recording.unscoped.create!(
      root_recording_id: @root_recording.id,
      parent_recording_id: parent_recording.id,
      recordable: boundary
    )
  end

  def define_actor_subclass(name)
    remove_actor_subclass(name)
    Object.const_set(name, Class.new(User))
  end

  def remove_actor_subclass(name)
    Object.send(:remove_const, name) if Object.const_defined?(name, false)
  end
end
