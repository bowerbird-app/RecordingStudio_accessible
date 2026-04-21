require_relative "../test_helper"

class HomePageTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user("admin@admin.com")
    @editor = create_user("editor@admin.com")
    @viewer = create_user("viewer@admin.com")
    @page_owner = create_user("page_owner@admin.com")
    @outsider = create_user("outsider@admin.com")

    workspace = Workspace.create!(name: "Integration Workspace")
    root_recording = RecordingStudio::Recording.unscoped.create!(recordable: workspace, parent_recording_id: nil)

    folder = Folder.create!(
      workspace: workspace,
      name: "Client onboarding",
      summary: "Folder-level access",
      position: 0
    )
    folder_recording = RecordingStudio::Recording.unscoped.create!(
      recordable: folder,
      parent_recording_id: root_recording.id,
      root_recording_id: root_recording.id
    )

    page = Page.create!(
      folder: folder,
      title: "Accessibility checklist",
      summary: "Page-level access",
      position: 0
    )
    page_recording = RecordingStudio::Recording.unscoped.create!(
      recordable: page,
      parent_recording_id: folder_recording.id,
      root_recording_id: root_recording.id
    )

    Card.create!(page: page, title: "Keyboard testing", body: "Verify keyboard-only navigation.", position: 0)

    grant_access(@admin, :admin, root_recording)
    grant_access(@editor, :edit, folder_recording, root_recording)
    grant_access(@viewer, :view, folder_recording, root_recording)
    grant_access(@page_owner, :edit, page_recording, root_recording)
  end

  test "home page renders the accessible demo and removed pages are absent" do
    sign_in @admin

    get "/"

    assert_response :success
    assert_includes @response.body, "Accessible"
    assert_includes @response.body, "Client onboarding"
    assert_includes @response.body, "Accessibility checklist"
    assert_includes @response.body, "Keyboard testing"
    assert_includes @response.body, @outsider.email
    assert_includes @response.body, "role=admin"
    refute_includes @response.body, "Recording Studio addon template"
    refute_includes @response.body, "href=\"/recording_studio\""
    refute_includes @response.body, "href=\"/up\""
  end

  test "removed health and recording studio pages are not routable" do
    sign_in @admin

    get "/recording_studio"
    assert_response :not_found

    get "/up"
    assert_response :not_found
  end

  test "addon route is mounted separately" do
    sign_in @admin

    get "/recording_studio_accessible"

    assert_response :success
    assert_includes @response.body, "Optional access-control addon"
  end

  private

  def create_user(email)
    User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def grant_access(user, role, parent_recording, root_recording = parent_recording)
    access = RecordingStudio::Access.create!(actor: user, role: role)
    RecordingStudio::Recording.unscoped.create!(
      root_recording_id: root_recording.id,
      parent_recording_id: parent_recording.id,
      recordable: access
    )
  end
end
