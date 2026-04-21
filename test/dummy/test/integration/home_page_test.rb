require_relative "../test_helper"

class HomePageTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "integration-admin@example.com", password: "Password", password_confirmation: "Password")
    @workspace = Workspace.create!(name: "Integration Workspace")
    @root_recording = RecordingStudio::Recording.unscoped.create!(recordable: @workspace, parent_recording_id: nil)
    access = RecordingStudio::Access.create!(actor: @user, role: :admin)
    RecordingStudio::Recording.unscoped.create!(
      root_recording_id: @root_recording.id,
      parent_recording_id: @root_recording.id,
      recordable: access
    )
  end

  test "home page renders seeded access summary for signed in users" do
    sign_in @user

    get "/"

    assert_response :success
    assert_includes @response.body, "Recording Studio Accessible"
    assert_includes @response.body, @workspace.name
  end

  test "addon route is mounted separately" do
    sign_in @user

    get "/recording_studio_accessible"

    assert_response :success
    assert_includes @response.body, "Optional access-control addon"
  end
end
