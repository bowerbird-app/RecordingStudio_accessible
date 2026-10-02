# frozen_string_literal: true

require_relative "../test_helper"

class ContextRolesTest < ActiveSupport::TestCase
  setup do
    @admin = create_user("context-roles-admin@example.com")
    @actor = create_user("context-roles-actor@example.com")
    @workspace = Workspace.create!(name: "Context Roles Workspace")
    @root_recording = create_root_recording(@workspace)
    bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(recording: @root_recording, actor: @admin)
    assert bootstrap.success?, bootstrap.error

    folder = Folder.create!(workspace: @workspace, name: "Downloads", summary: "Files", position: 0)
    @folder_recording = create_child_recording(recordable: folder, parent_recording: @root_recording)
    Folder.accessible_roles :view, :download
  end

  teardown do
    Folder.remove_instance_variable(:@accessible_role_set) if Folder.instance_variable_defined?(:@accessible_role_set)
  end

  test "default hierarchy still ranks view below edit below admin" do
    viewer = create_user("context-roles-viewer@example.com")
    editor = create_user("context-roles-editor@example.com")
    create_direct_access_recording(actor: viewer, role: :view, parent_recording: @root_recording)
    create_direct_access_recording(actor: editor, role: :edit, parent_recording: @root_recording)

    assert_equal :view, RecordingStudioAccessible.role_for(actor: viewer, recording: @root_recording)
    assert RecordingStudioAccessible.authorized?(actor: viewer, recording: @root_recording, role: :view)
    refute RecordingStudioAccessible.authorized?(actor: viewer, recording: @root_recording, role: :edit)
    assert RecordingStudioAccessible.authorized?(actor: editor, recording: @root_recording, role: :view)
    assert RecordingStudioAccessible.authorized?(actor: editor, recording: @root_recording, role: :edit)
    refute RecordingStudioAccessible.authorized?(actor: editor, recording: @root_recording, role: :admin)
  end

  test "direct grants accept only the target context roles" do
    assert_equal %w[view edit admin], RecordingStudioAccessible.roles_for(@root_recording)
    assert_equal %w[view download], RecordingStudioAccessible.roles_for(@folder_recording)

    download = RecordingStudioAccessible.grant_access(
      recording: @folder_recording, actor: @actor, role: :download, manager_actor: @admin
    )
    edit_on_folder = RecordingStudioAccessible.grant_access(
      recording: @folder_recording, actor: create_user("context-roles-folder-edit@example.com"),
      role: :edit, manager_actor: @admin
    )
    download_on_root = RecordingStudioAccessible.grant_access(
      recording: @root_recording, actor: create_user("context-roles-root-download@example.com"),
      role: :download, manager_actor: @admin
    )

    assert download.success?, download.error
    assert_equal "download", download.value.recordable.role
    assert edit_on_folder.failure?
    assert_equal "Role is invalid", edit_on_folder.error
    assert download_on_root.failure?
    assert_equal "Role is invalid", download_on_root.error
  end

  test "any declared role on the path satisfies an explicit role set" do
    create_direct_access_recording(actor: @actor, role: :download, parent_recording: @folder_recording)

    assert RecordingStudioAccessible.authorized_for_any_role?(
      actor: @actor, recording: @folder_recording, roles: [:download]
    )
    assert RecordingStudioAccessible.authorized_for_any_role?(
      actor: @actor, recording: @folder_recording, roles: %i[download edit admin]
    )
    refute RecordingStudioAccessible.authorized_for_any_role?(
      actor: @actor, recording: @folder_recording, roles: %i[api admin]
    )
    refute RecordingStudioAccessible.authorized?(actor: @actor, recording: @folder_recording, role: :edit)
    refute RecordingStudioAccessible.authorized?(actor: @actor, recording: @folder_recording, role: :view)
  end

  test "an inherited hierarchy role matches only when the caller lists it" do
    create_direct_access_recording(actor: @actor, role: :edit, parent_recording: @root_recording)

    assert_nil RecordingStudioAccessible::DirectAccessQuery.access_recordings_for_actor(
      recording: @folder_recording, actor: @actor
    ).first
    assert RecordingStudioAccessible.authorized_for_any_role?(
      actor: @actor, recording: @folder_recording, roles: %i[download edit admin]
    )
    refute RecordingStudioAccessible.authorized_for_any_role?(
      actor: @actor, recording: @folder_recording, roles: [:download]
    )
    refute RecordingStudioAccessible.authorized_for_any_role?(
      actor: @actor, recording: @folder_recording, roles: %i[api admin]
    )
  end

  test "an inherited view grant does not satisfy a higher explicit role set" do
    create_direct_access_recording(actor: @actor, role: :view, parent_recording: @root_recording)

    refute RecordingStudioAccessible.authorized_for_any_role?(
      actor: @actor, recording: @folder_recording, roles: %i[download edit admin]
    )
    refute RecordingStudioAccessible.authorized_for_any_role?(
      actor: @actor, recording: @folder_recording, roles: []
    )
    refute RecordingStudioAccessible.authorized_for_any_role?(
      actor: nil, recording: @folder_recording, roles: [:view]
    )
  end

  test "invitations and updates use the target context roles" do
    invited = RecordingStudioAccessible.invite_access(
      recording: @folder_recording, email: "download-invite@example.com", role: :download, manager_actor: @admin
    )
    rejected = RecordingStudioAccessible.invite_access(
      recording: @folder_recording, email: "edit-invite@example.com", role: :edit, manager_actor: @admin
    )

    assert invited.success?, invited.error
    assert_equal "download", invited.value.pending.role
    assert rejected.failure?
    assert_equal "Role is invalid", rejected.error

    granted = RecordingStudioAccessible.grant_access(
      recording: @folder_recording, actor: @actor, role: :view, manager_actor: @admin
    )
    assert granted.success?, granted.error

    promoted = RecordingStudioAccessible::Services::UpdateRecordingAccess.call(
      recording: @folder_recording, access_recording: granted.value, role: :download, manager_actor: @admin
    )
    refused = RecordingStudioAccessible::Services::UpdateRecordingAccess.call(
      recording: @folder_recording, access_recording: granted.value, role: :edit, manager_actor: @admin
    )

    assert promoted.success?, promoted.error
    assert_equal "download", promoted.value.recordable.role
    assert refused.failure?
    assert_equal "Role is invalid", refused.error
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end
end
