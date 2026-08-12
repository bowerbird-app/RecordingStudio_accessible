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
    @root_recording = create_root_recording(workspace)

    folder = Folder.create!(
      workspace: workspace,
      name: "Client onboarding",
      summary: "Folder-level access",
      position: 0
    )
    @folder_recording = create_child_recording(recordable: folder, parent_recording: @root_recording)

    page = Page.create!(
      folder: folder,
      title: "Accessibility checklist",
      summary: "Page-level access",
      position: 0
    )
    @page_recording = create_child_recording(recordable: page, parent_recording: @folder_recording)

    Card.create!(page: page, title: "Keyboard testing", body: "Verify keyboard-only navigation.", position: 0)

    grant_access(@admin, :admin, @root_recording)
    grant_access(@editor, :edit, @root_recording)
    grant_access(@viewer, :view, @root_recording)
  end

  test "home page renders the accessible demo and removed pages are absent" do
    sign_in @admin
    switch_to_root(@root_recording)

    get "/"

    assert_response :success
    assert_match %r{<html[^>]*data-theme="rounded"}, @response.body
    assert_includes @response.body, "Recording Studio Accessible Demo"
    assert_includes @response.body, "Message groups"
    assert_includes @response.body, "href=\"/message_groups\""
    assert_includes @response.body, "Client onboarding"
    assert_includes @response.body, "Accessibility checklist"
    refute_includes @response.body, "0 access"
    assert_includes @response.body, "Pages not allowed to add access"
    refute_includes @response.body, "Workspace:"
    refute_includes @response.body, "people with access"
    refute_includes @response.body, "admin@admin.com (admin)"
    refute_includes @response.body, @outsider.email
    assert_includes @response.body, "href=\"/recording_studio_accessible/recordings/#{@root_recording.id}/accesses"
    assert_includes @response.body, "href=\"/recording_studio_accessible/recordings/#{@folder_recording.id}/accesses"
    refute_includes @response.body, "href=\"/recording_studio_accessible/recordings/#{@page_recording.id}/accesses\""
    refute_includes @response.body, "Recording Studio addon template"
    refute_includes @response.body, "href=\"/recording_studio\""
    refute_includes @response.body, "href=\"/up\""
  end

  test "admin sees my access link in the top nav" do
    sign_in @admin
    switch_to_root(@root_recording)
    workspace = @root_recording.recordable

    get "/"

    assert_response :success
    assert_includes @response.body, "My access"
    assert_includes @response.body, "href=\"/recording_studio_accessible/workspaces/#{workspace.id}/actor_access_points"
    assert_includes @response.body, "actor_type=User"
    assert_includes @response.body, "actor_id=#{@admin.id}"
  end

  test "top nav root switcher lists accessible workspaces but excludes other root types" do
    alternate_workspace = Workspace.create!(name: "Alternate Workspace")
    alternate_root_recording = create_root_recording(alternate_workspace)
    grant_access(@admin, :admin, alternate_root_recording)

    message_root = MessageRoot.create!(name: "Unswitched message root")
    message_root_recording = create_root_recording(message_root)
    grant_access(@admin, :admin, message_root_recording)

    sign_in @admin

    get "/"

    assert_response :success
    assert_includes @response.body, @root_recording.recordable.name
    assert_includes @response.body, alternate_workspace.name
    refute_includes @response.body, message_root.name
    assert_includes @response.body, 'action="/recording_studio_root_switchable/v1/root_switch?scope=workspaces"'
  end

  test "top nav root switcher persists the selected workspace" do
    alternate_workspace = Workspace.create!(name: "Selected Workspace")
    alternate_root_recording = create_root_recording(alternate_workspace)
    grant_access(@admin, :admin, alternate_root_recording)

    sign_in @admin

    patch "/recording_studio_root_switchable/v1/root_switch?scope=workspaces", params: {
      root_switch: { root_recording_id: alternate_root_recording.id, return_to: "/" }
    }

    assert_redirected_to "/"
    assert RecordingStudio::RootSwitchable::Selection.exists?(
      actor: @admin,
      scope_key: "workspaces",
      root_recording: alternate_root_recording
    )
  end

  test "home page renders the selected workspace after a root switch" do
    selected_workspace = Workspace.create!(name: "Selected Workspace")
    selected_root_recording = create_root_recording(selected_workspace)
    selected_folder = Folder.create!(
      workspace: selected_workspace,
      name: "Selected folder",
      summary: "Selected workspace content",
      position: 0
    )
    create_child_recording(recordable: selected_folder, parent_recording: selected_root_recording)
    selected_page = Page.create!(
      folder: selected_folder,
      title: "Selected page",
      summary: "Selected workspace page",
      position: 0
    )
    create_child_recording(
      recordable: selected_page,
      parent_recording: RecordingStudio::Recording.unscoped.find_by!(recordable: selected_folder)
    )
    grant_access(@admin, :admin, selected_root_recording)

    sign_in @admin

    patch "/recording_studio_root_switchable/v1/root_switch?scope=workspaces", params: {
      root_switch: { root_recording_id: selected_root_recording.id, return_to: "/" }
    }
    follow_redirect!

    assert_response :success
    assert_includes @response.body, selected_workspace.name
    assert_includes @response.body, selected_folder.name
    assert_includes @response.body, selected_page.title
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

  test "non-admin users do not see mounted addon docs links" do
    sign_in @viewer

    get "/"

    assert_response :success
    refute_includes @response.body, 'href="/recording_studio_accessible/overview"'
    refute_includes @response.body, 'href="/recording_studio_accessible/email_template"'
    refute_includes @response.body, "My access"
    refute_includes @response.body, "actor_id=#{@viewer.id}"
  end

  test "non-admin users are redirected away from mounted addon docs and previews" do
    sign_in @viewer

    get "/recording_studio_accessible"
    assert_response :redirect
    assert_redirected_to "/"

    get "/recording_studio_accessible/methods"
    assert_response :redirect
    assert_redirected_to "/"

    get "/recording_studio_accessible/email_template"
    assert_response :redirect
    assert_redirected_to "/"
  end

  test "methods page renders the documented access APIs" do
    sign_in @admin

    get "/recording_studio_accessible/methods"

    assert_response :success
    assert_includes @response.body, "Methods"
    assert_includes @response.body, "Access APIs provided by this gem"
    assert_includes @response.body, "href=\"/recording_studio_accessible/methods\""
    assert_includes @response.body, "RecordingStudioAccessible.grant_access"
    assert_includes @response.body, "RecordingStudioAccessible.authorized?"
    assert_includes @response.body, "RecordingStudioAccessible.role_for"
    assert_includes @response.body, "RecordingStudioAccessible.root_recording_ids_for"
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

  test "user invites page explains missing-user handling and setup options" do
    sign_in @admin

    get "/recording_studio_accessible/user_invites"

    assert_response :success
    assert_includes @response.body, "User invites"
    assert_includes @response.body, "How missing emails are resolved during access grants"
    assert_includes @response.body, "href=\"/recording_studio_accessible/user_invites\""
    assert_includes @response.body, "User with email ... was not found"
    assert_includes @response.body, "before the grant continues"
    assert_includes @response.body, "requires_resolution"
    assert_includes @response.body, "config.access_management_actor_email_resolver"
    assert_includes @response.body, "config.access_management_missing_actor_handler"
    assert_includes @response.body, 'Review #{normalized_email} before granting access'
    assert_includes @response.body, "controller.main_app.url_for"
    assert_includes @response.body, "text-[var(--surface-content-color)]"
    refute_includes @response.body, "text-(--surface-content-color)"
  end

  test "email template page renders the default access granted email preview" do
    sign_in @admin

    get "/recording_studio_accessible/email_template"

    shared_item_url_pattern = %r{http://[^/]+/workspaces/#{Regexp.escape(@root_recording.recordable.id.to_s)}}

    assert_response :success
    assert_includes @response.body, "Email template"
    assert_includes @response.body, "Default message sent when access is granted"
    assert_includes @response.body, "href=\"/recording_studio_accessible/email_template\""
    assert_includes @response.body, "Message details"
    assert_includes @response.body, "You were given access"
    assert_includes @response.body, "no-reply@example.com"
    assert_includes @response.body, @viewer.email
    assert_match %r{Granted by\s+Admin}, @response.body
    assert_includes @response.body, "HTML preview"
    assert_match %r{Admin\s+granted you &lt;strong&gt;view&lt;/strong&gt; access to #{@root_recording.recordable.name}}, @response.body
    assert_match %r{href=&quot;#{shared_item_url_pattern.source}&quot;}, @response.body
    assert_includes @response.body, "Text preview"
    assert_match %r{Admin granted you view access to #{@root_recording.recordable.name}\.\s*Open the shared item: #{shared_item_url_pattern.source}}, @response.body
  end

  test "home page renders access actions section" do
    sign_in @admin

    get "/"

    assert_response :success
    assert_includes @response.body, "Access Actions"
    assert_includes @response.body, "Manage workspace"
    assert_includes @response.body, "Export data"
    assert_includes @response.body, "Approved"
    assert_includes @response.body, "Denied"
    assert_includes @response.body, "href=\"/access_actions/manage_workspace\""
    assert_includes @response.body, "href=\"/access_actions/export_data\""
  end

  test "admin sees approved on action detail page" do
    sign_in @admin

    get "/access_actions/manage_workspace"

    assert_response :success
    assert_includes @response.body, "Access approved"
  end

  test "admin sees denied on export action detail page" do
    sign_in @admin

    get "/access_actions/export_data"

    assert_response :success
    assert_includes @response.body, "Access denied"
  end

  test "unknown action detail page is not found" do
    sign_in @admin

    get "/access_actions/not_registered"

    assert_response :not_found
  end

  test "viewer sees denied on action detail page" do
    sign_in @viewer

    get "/access_actions/manage_workspace"

    assert_response :success
    assert_includes @response.body, "Access denied"
    assert_includes @response.body, "You are not authorized"
  end

  test "viewer sees both actions denied on home page" do
    sign_in @viewer

    get "/"

    assert_response :success
    assert_includes @response.body, "Access Actions"
    assert_equal 2, @response.body.scan("Denied").size
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def grant_access(user, role, parent_recording, root_recording = parent_recording)
    create_direct_access_recording(actor: user, role: role, parent_recording: parent_recording)
  end

  def switch_to_root(root_recording)
    patch "/recording_studio_root_switchable/v1/root_switch?scope=workspaces", params: {
      root_switch: { root_recording_id: root_recording.id, return_to: "/" }
    }

    assert_redirected_to "/"
  end
end
