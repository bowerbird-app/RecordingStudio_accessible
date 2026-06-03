require_relative "../test_helper"

class UserShowPageTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user("admin@admin.com")
    @editor = create_user("editor@admin.com")
    @viewer = create_user("viewer@admin.com")
    @page_owner = create_user("page_owner@admin.com")

    workspace = Workspace.create!(name: "000 Integration Workspace")
    root_recording = create_root_recording(workspace)

    folder = Folder.create!(
      workspace: workspace,
      name: "Client onboarding",
      summary: "Folder-level access",
      position: 0
    )
    folder_recording = create_child_recording(recordable: folder, parent_recording: root_recording)

    page = Page.create!(
      folder: folder,
      title: "Accessibility checklist",
      summary: "Page-level access",
      position: 0
    )
    page_recording = create_child_recording(recordable: page, parent_recording: folder_recording)

    grant_access(@admin, :admin, root_recording)
    grant_access(@editor, :edit, root_recording)
  end

  test "home page does not list workspace access users" do
    sign_in @admin

    get "/"

    assert_response :success
    refute_includes @response.body, "people with access"
    refute_includes @response.body, "#{@admin.email} (admin)"
    refute_includes @response.body, user_path(@admin)
    refute_includes @response.body, user_path(@editor)
  end

  test "user show page lists items the user can access" do
    sign_in @admin

    get user_path(@editor)

    assert_response :success
    assert_includes @response.body, @editor.email
    assert_includes @response.body, "Accessible items"
    assert_includes @response.body, "Client onboarding"
    assert_includes @response.body, "Accessibility checklist"
    assert_includes @response.body, "Folder"
    assert_includes @response.body, "Page"
    assert_includes @response.body, "edit access"
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def grant_access(user, role, parent_recording, root_recording = parent_recording)
    create_direct_access_recording(actor: user, role: role, parent_recording: parent_recording)
  end
end
