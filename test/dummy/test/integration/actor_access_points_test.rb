require_relative "../test_helper"

class ActorAccessPointsTest < ActionDispatch::IntegrationTest
  setup do
    @original_access_actor_types = RecordingStudioAccessible.configuration.access_actor_types
    @original_mounted_page_authorizer = RecordingStudioAccessible.configuration.mounted_page_authorizer
    @admin = create_user("admin@admin.com")
    @actor = create_user("actor@admin.com")

    @workspace = Workspace.create!(name: "Actor Access Workspace")
    @workspace_root_recording = create_root_recording(@workspace)

    folder = Folder.create!(
      workspace: @workspace,
      name: "Workspace folder",
      summary: "Access scope",
      position: 0
    )
    @folder_recording = create_child_recording(recordable: folder, parent_recording: @workspace_root_recording)

    other_workspace = Workspace.create!(name: "Other Workspace")
    @other_root_recording = create_root_recording(other_workspace)

    other_folder = Folder.create!(
      workspace: other_workspace,
      name: "Other folder",
      summary: "Other scope",
      position: 0
    )
    @other_folder_recording = create_child_recording(recordable: other_folder, parent_recording: @other_root_recording)

    grant_access(@admin, :admin, @workspace_root_recording)
    grant_access(@actor, :view, @workspace_root_recording)
    grant_access(@actor, :edit, @folder_recording)
    grant_access(@actor, :admin, @other_folder_recording)
  end

  teardown do
    RecordingStudioAccessible.configuration.access_actor_types = @original_access_actor_types
    RecordingStudioAccessible.configuration.mounted_page_authorizer = @original_mounted_page_authorizer
  end

  test "admin can view actor access points within a workspace" do
    sign_in @admin

    get actor_access_points_path, params: {
      actor_type: "User",
      actor_id: @actor.id,
      back_url: "/users/#{@actor.id}",
      anchor_url: "/#workspace-access"
    }

    assert_response :success
    assert_match %r{<html[^>]*data-theme="rounded"}, @response.body
    assert_includes @response.body, 'data-controller="flat-pack--page-nav"'
    assert_includes @response.body, "#{@actor.email} access points"
    assert_includes @response.body, "Workspace: #{@workspace.name}"
    assert_includes @response.body, "<table"
    assert_includes @response.body, "Access point"
    assert_includes @response.body, "Role"
    assert_includes @response.body, "Access recording"
    assert_includes @response.body, @workspace.name
    assert_includes @response.body, "Workspace folder"
    assert_includes @response.body, "View"
    assert_includes @response.body, "Edit"
    refute_includes @response.body, "Other folder"
    assert_includes @response.body, 'href="/#workspace-access"'
  end

  test "actor access points page rejects unsafe anchor_url" do
    sign_in @admin

    get actor_access_points_path, params: {
      actor_type: "User",
      actor_id: @actor.id,
      back_url: "/users/#{@actor.id}",
      anchor_url: "//evil.example/access"
    }

    assert_response :success
    assert_includes @response.body, "href=\"/users/#{@actor.id}\""
    refute_includes @response.body, "evil.example"
  end

  test "configured access actor types constrain actor access point lookup" do
    RecordingStudioAccessible.configuration.access_actor_types = [ "Workspace" ]
    sign_in @admin

    get actor_access_points_path, params: {
      actor_type: "User",
      actor_id: @actor.id
    }

    assert_response :not_found
  end

  test "blank access actor types fail closed for actor access point lookup" do
    RecordingStudioAccessible.configuration.access_actor_types = []
    sign_in @admin

    get actor_access_points_path, params: {
      actor_type: "User",
      actor_id: @actor.id
    }

    assert_response :not_found
    refute_includes @response.body, @actor.email
  end

  test "actor access point lookup does not reveal actors without workspace access" do
    actor_without_workspace_access = create_user("other-actor@admin.com")
    create_direct_access_recording(
      actor: actor_without_workspace_access,
      role: :admin,
      parent_recording: @other_root_recording
    )
    sign_in @admin

    get actor_access_points_path, params: {
      actor_type: "User",
      actor_id: actor_without_workspace_access.id
    }

    assert_response :not_found
    refute_includes @response.body, actor_without_workspace_access.email
  end

  test "broad mounted page access cannot view another actor access points" do
    viewer = create_user("viewer@admin.com")
    RecordingStudioAccessible.configuration.mounted_page_authorizer = ->(**) { true }
    sign_in viewer

    get actor_access_points_path, params: {
      actor_type: "User",
      actor_id: @actor.id
    }

    assert_response :not_found
    refute_includes @response.body, @actor.email
  end

  test "current actor can view their own access points" do
    sign_in @actor

    get actor_access_points_path, params: {
      actor_type: "User",
      actor_id: @actor.id
    }

    assert_response :success
    assert_includes @response.body, "#{@actor.email} access points"
  end

  test "malformed actor ids fail closed" do
    sign_in @admin

    get actor_access_points_path, params: {
      actor_type: "User",
      actor_id: "not-a-uuid"
    }

    assert_response :not_found
  end

  test "malformed workspace ids fail closed" do
    sign_in @admin

    get "/recording_studio_accessible/workspaces/not-a-uuid/actor_access_points", params: {
      actor_type: "User",
      actor_id: @actor.id
    }

    assert_response :not_found
  end

  test "configured access actor types reject unknown constants before lookup" do
    RecordingStudioAccessible.configuration.access_actor_types = [ "User" ]
    sign_in @admin

    get actor_access_points_path, params: {
      actor_type: "Kernel",
      actor_id: @actor.id
    }

    assert_response :not_found
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def grant_access(user, role, parent_recording)
    create_direct_access_recording(actor: user, role: role, parent_recording: parent_recording)
  end

  def actor_access_points_path
    "/recording_studio_accessible/workspaces/#{@workspace.id}/actor_access_points"
  end
end
