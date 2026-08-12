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

  test "resolves the strongest direct or inherited role while preserving direct access rows" do
    child_access = grant_access(@viewer, :view, @folder_recording, @root_recording)
    assert_equal :view, child_access.recordable.role.to_sym

    grant_access(@viewer, :admin, @root_recording)

    assert_equal :admin, RecordingStudioAccessible.role_for(actor: @viewer, recording: @folder_recording)
    assert RecordingStudioAccessible.authorized?(actor: @viewer, recording: @folder_recording, role: :admin)
  end

  test "does not authorize admin when the strongest role is edit" do
    grant_access(@editor, :edit, @root_recording)
    grant_access(@editor, :view, @folder_recording, @root_recording)

    assert_equal :edit, RecordingStudioAccessible.role_for(actor: @editor, recording: @folder_recording)
    refute RecordingStudioAccessible.authorized?(actor: @editor, recording: @folder_recording, role: :admin)
  end

  test "inherits root access on descendant recordings" do
    grant_access(@editor, :edit, @root_recording)

    assert_equal :edit, RecordingStudioAccessible.role_for(actor: @editor, recording: @page_recording)
    assert RecordingStudioAccessible.authorized?(actor: @editor, recording: @page_recording, role: :view)
  end

  test "root listing helpers remain aligned" do
    grant_access(@admin, :admin, @root_recording)

    expected_recordings = [ @root_recording ]
    expected_ids = expected_recordings.map(&:id)

    assert_equal expected_recordings, RecordingStudioAccessible.root_recordings_for(actor: @admin)
    assert_equal expected_ids, RecordingStudioAccessible.root_recording_ids_for(actor: @admin)
  end

  test "root listing helpers resolve descendant grants to their RecordingStudio root" do
    access_recording = grant_access(@admin, :admin, @folder_recording, @root_recording)

    assert_equal @root_recording.id, @root_recording.root_recording_id
    assert_equal @root_recording.id, @folder_recording.root_recording_id
    assert_equal @root_recording.id, access_recording.root_recording_id
    assert_equal [ @root_recording ], RecordingStudioAccessible.root_recordings_for(actor: @admin)
    assert_equal [ @root_recording.id ], RecordingStudioAccessible.root_recording_ids_for(actor: @admin)
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
    assert_equal [ access_recording.id ],
                 RecordingStudioAccessible::DirectAccessQuery.access_recordings_for_actor(
                    recording: @root_recording,
                    actor: special_user
                  ).pluck(:id)
    assert_equal [ @root_recording.id ],
                 RecordingStudioAccessible.root_recording_ids_for(actor: special_user)
  ensure
    remove_actor_subclass("ResolverSpecialUser")
  end

  test "malformed same-parent duplicates resolve to their strongest valid role regardless of row order" do
    older = grant_access(@viewer, :admin, @root_recording)
    newer = grant_access(create_user("resolver-duplicate@example.com"), :view, @root_recording)
    duplicate_access_for!(newer, @viewer)

    assert_equal :admin, RecordingStudioAccessible.role_for(actor: @viewer, recording: @root_recording)

    update_access_role!(older, :view)
    update_access_role!(newer, :admin)

    assert_equal :admin, RecordingStudioAccessible.role_for(actor: @viewer, recording: @root_recording)
  end

  test "malformed duplicates ignore invalid and trashed roles without affecting another parent" do
    root_view = grant_access(@viewer, :view, @root_recording)
    root_invalid = grant_access(create_user("resolver-invalid@example.com"), :edit, @root_recording)
    duplicate_access_for!(root_invalid, @viewer, role: 99)
    folder_edit = grant_access(@viewer, :edit, @folder_recording, @root_recording)
    folder_trashed = grant_access(create_user("resolver-trashed@example.com"), :admin, @folder_recording, @root_recording)
    duplicate_access_for!(folder_trashed, @viewer)
    folder_trashed.update_column(:trashed_at, Time.current)

    assert_equal :view, RecordingStudioAccessible.role_for(actor: @viewer, recording: @root_recording)
    assert_equal :edit, RecordingStudioAccessible.role_for(actor: @viewer, recording: @folder_recording)
    assert_equal :edit, RecordingStudioAccessible.role_for(actor: @viewer, recording: @page_recording)
    assert_equal "view", root_view.recordable.role
    assert_equal "edit", folder_edit.recordable.role
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def grant_access(user, role, parent_recording, root_recording = parent_recording)
    create_direct_access_recording(actor: user, role: role, parent_recording: parent_recording)
  end

  def duplicate_access_for!(access_recording, actor, role: nil)
    connection = ActiveRecord::Base.connection
    assignments = [
      "actor_type = #{connection.quote(RecordingStudioAccessible::ActorType.for(actor))}",
      "actor_id = #{connection.quote(actor.id)}"
    ]
    assignments << "role = #{connection.quote(stored_role(role))}" unless role.nil?
    connection.execute(<<~SQL.squish)
      UPDATE recording_studio_accesses
      SET #{assignments.join(', ')}
      WHERE id = #{connection.quote(access_recording.recordable_id)}
    SQL
  end

  def stored_role(role)
    RecordingStudio::Access.roles.fetch(role.to_s, role)
  end

  def update_access_role!(access_recording, role)
    connection = ActiveRecord::Base.connection
    connection.execute(<<~SQL.squish)
      UPDATE recording_studio_accesses SET role = #{connection.quote(stored_role(role))}
      WHERE id = #{connection.quote(access_recording.recordable_id)}
    SQL
  end

  def define_actor_subclass(name)
    remove_actor_subclass(name)
    Object.const_set(name, Class.new(User))
  end

  def remove_actor_subclass(name)
    Object.send(:remove_const, name) if Object.const_defined?(name, false)
  end
end
