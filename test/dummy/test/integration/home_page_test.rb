require_relative "../test_helper"
require "securerandom"

class HomePageTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user("admin@admin.com")
    @editor = create_user("editor@admin.com")
    @viewer = create_user("viewer@admin.com")
    @page_owner = create_user("page_owner@admin.com")
    @outsider = create_user("outsider@admin.com")

    workspace = Workspace.create!(name: "000 Integration Workspace #{SecureRandom.hex(4)}")
    @root_recording = RecordingStudio::Recording.unscoped.create!(recordable: workspace, parent_recording_id: nil)

    folder = Folder.create!(
      workspace: workspace,
      name: "Client onboarding",
      summary: "Folder-level access",
      position: 0
    )
    @folder_recording = RecordingStudio::Recording.unscoped.create!(
      recordable: folder,
      parent_recording_id: @root_recording.id,
      root_recording_id: @root_recording.id
    )

    page = Page.create!(
      folder: folder,
      title: "Accessibility checklist",
      summary: "Page-level access",
      position: 0
    )
    @page_recording = RecordingStudio::Recording.unscoped.create!(
      recordable: page,
      parent_recording_id: @folder_recording.id,
      root_recording_id: @root_recording.id
    )

    Card.create!(page: page, title: "Keyboard testing", body: "Verify keyboard-only navigation.", position: 0)

    grant_access(@admin, :admin, @root_recording)
    grant_access(@editor, :edit, @folder_recording, @root_recording)
    grant_access(@viewer, :view, @folder_recording, @root_recording)
    grant_access(@page_owner, :edit, @page_recording, @root_recording)
  end

  test "home page renders the accessible demo and removed pages are absent" do
    sign_in @admin

    get "/"

    assert_response :success
    assert_includes @response.body, "Recording Studio Accessible Demo"
    assert_includes @response.body, "Workspace:"
    assert_includes @response.body, "People with workspace access"
    assert_includes @response.body, "Manage workspace access"
    assert_includes @response.body, "/recording_studio_accessible/recordings/"
    assert_includes @response.body, "/accesses"
    assert_includes @response.body, "Client onboarding"
    assert_includes @response.body, "Accessibility checklist"
    assert_includes @response.body, "href=\"/recording_studio_accessible/recordings/#{@folder_recording.id}/accesses\""
    assert_includes @response.body, "href=\"/recording_studio_accessible/recordings/#{@page_recording.id}/accesses\""
    assert_includes @response.body, "admin@admin.com (admin)"
    assert_includes @response.body, "2 people with direct access"
    assert_includes @response.body, "1 person with direct access"
    refute_includes @response.body, "editor@admin.com (edit)"
    refute_includes @response.body, "viewer@admin.com (view)"
    refute_includes @response.body, "page_owner@admin.com (edit)"
    refute_includes @response.body, @outsider.email
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

  test "methods page renders the documented access APIs" do
    sign_in @admin

    get "/recording_studio_accessible/methods"

    assert_response :success
    assert_includes @response.body, "Methods"
    assert_includes @response.body, "Access APIs provided by this gem"
    assert_includes @response.body, "href=\"/recording_studio_accessible/methods\""
    assert_includes @response.body, "RecordingStudio::Access.create!"
    assert_includes @response.body, "RecordingStudio::AccessBoundary.create!"
    assert_includes @response.body, "RecordingStudio::Services::AccessCheck.allowed?"
    assert_includes @response.body, "RecordingStudio::Services::AccessCheck.root_recording_ids_for"
  end

  test "overview page renders only the title and subtitle" do
    sign_in @admin

    get "/recording_studio_accessible/overview"

    assert_response :success
    assert_includes @response.body, "Overview"
    assert_includes @response.body, "How access is structured"
    assert_includes @response.body, "href=\"/recording_studio_accessible/overview\""
    assert_includes @response.body, "Add access to something"
    assert_includes @response.body, "Access is granted by adding a child recording using an access recordable."
    assert_includes @response.body, "- Page"
    assert_includes @response.body, "-- Access"
  end

  test "boundaries page renders the rebuilt guidance content" do
    sign_in @admin

    get "/recording_studio_accessible/boundaries"

    assert_response :success
    assert_includes @response.body, "Boundaries"
    assert_includes @response.body, "How to limit access to children"
    assert_includes @response.body, "href=\"/recording_studio_accessible/boundaries\""
    assert_includes @response.body, "What a boundary is"
    assert_includes @response.body, "How resolution works"
    assert_includes @response.body, "When access is denied"
    assert_includes @response.body, "Use a boundary when one branch of a workspace needs stricter rules than the rest."
    refute_includes @response.body, "Boundary hierarchy examples"
    refute_includes @response.body, "Workspace root"
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
end
