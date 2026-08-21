require_relative "../test_helper"

class WorkspaceBootstrapTest < ActionDispatch::IntegrationTest
  setup do
    @owner = create_user("bootstrap-ui-owner@example.com")
    @invitee = create_user("editor@admin.com")
  end

  test "creating a workspace bootstraps the signed-in user as first admin" do
    sign_in @owner

    assert_difference -> { Workspace.count }, 1 do
      post workspaces_path, params: { workspace: { name: "Fresh Studio" } }
    end

    assert_redirected_to root_path
    follow_redirect!

    workspace = Workspace.find_by!(name: "Fresh Studio")
    root = RecordingStudio.root_recording_for(workspace)

    assert_response :success
    assert_includes @response.body, "You’re in. Fresh Studio is yours"
    assert_includes @response.body, "Fresh Studio"
    assert RecordingStudioAccessible.authorized?(actor: @owner, recording: root, role: :admin)

    get recording_studio_accessible.recording_accesses_path(root, back_url: "/", anchor_url: "/")
    assert_response :success
    assert_includes @response.body, "Manage access"
    assert_includes @response.body, @owner.email
  end

  test "blank workspace name does not bootstrap" do
    sign_in @owner

    assert_no_difference -> { Workspace.count } do
      post workspaces_path, params: { workspace: { name: "   " } }
    end

    assert_redirected_to root_path
    follow_redirect!
    assert_includes @response.body, "Give this workspace a name first."
  end

  test "failed bootstrap does not leave an orphaned workspace" do
    sign_in @owner
    original_access_actor_types = RecordingStudioAccessible.configuration.access_actor_types
    RecordingStudioAccessible.configuration.access_actor_types = [ "Workspace" ]

    assert_no_difference -> { Workspace.count } do
      assert_no_difference -> { RecordingStudio::Recording.unscoped.count } do
        post workspaces_path, params: { workspace: { name: "Orphan Studio" } }
      end
    end

    assert_redirected_to root_path
    follow_redirect!
    assert_includes @response.body, "Couldn’t make you the first owner"
    refute Workspace.exists?(name: "Orphan Studio")
  ensure
    RecordingStudioAccessible.configuration.access_actor_types = original_access_actor_types
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end
end
