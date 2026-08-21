require_relative "../test_helper"

class MessageGroupsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user("admin@admin.com")
    @outsider = create_user("outsider@admin.com")

    @workspace = Workspace.create!(name: "Accessible Demo Workspace")
    @workspace_root_recording = create_root_recording(@workspace)

    @message_root = MessageRoot.create!(name: "Messages Root")
    @message_root_recording = create_root_recording(@message_root)
    @message_group = MessageGroup.create!(
      message_root: @message_root,
      name: "Client launch thread",
      summary: "A message group visible through workspace access.",
      position: 0
    )
    @message_group_recording = create_child_recording(
      recordable: @message_group,
      parent_recording: @message_root_recording
    )

    create_direct_access_recording(actor: @admin, role: :admin, parent_recording: @workspace_root_recording)

    bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(
      recording: @message_group_recording,
      actor: @admin
    )
    raise bootstrap.error if bootstrap.failure?

    later = RecordingStudioAccessible.grant_access(
      recording: @message_group_recording,
      actor: @workspace,
      role: :view,
      manager_actor: @admin
    )
    raise later.error if later.failure?
  end

  test "workspace member can see message groups through workspace access" do
    sign_in @admin

    get "/"
    assert_response :success
    assert_includes @response.body, "Message groups"
    assert_includes @response.body, "href=\"/message_groups\""
    assert_includes @response.body, @message_group.name

    get "/message_groups"

    assert_response :success
    assert_includes @response.body, "Message groups"
    assert_includes @response.body, "Demo of access through #{@workspace.name}"
    assert_includes @response.body, @message_group.name
    assert_includes @response.body, @message_root.name
    assert_includes @response.body, "Direct access"
    assert_includes @response.body, "Through access"
    assert_includes @response.body, "Yes"
    assert_includes @response.body, "Admin"
  end

  test "outsider cannot see message groups through workspace access" do
    sign_in @outsider

    get "/message_groups"

    assert_response :success
    refute_includes @response.body, @message_group.name
    assert_includes @response.body, "No message groups"
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end
end
