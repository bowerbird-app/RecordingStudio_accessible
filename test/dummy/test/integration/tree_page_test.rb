# frozen_string_literal: true

require_relative "../test_helper"

class TreePageTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.find_by(email: "admin@admin.com") ||
             User.create!(email: "admin@admin.com", password: "Password", password_confirmation: "Password")
    workspace = Workspace.create!(name: "Tree Workspace")
    @root_recording = create_root_recording(workspace)
    folder = Folder.create!(workspace: workspace, name: "Tree folder", summary: "Nested", position: 0)
    @folder_recording = create_child_recording(recordable: folder, parent_recording: @root_recording)
    create_direct_access_recording(actor: @admin, role: :admin, parent_recording: @root_recording)
  end

  test "tree page uses the FlatPack Tree component" do
    sign_in @admin

    get "/tree"

    assert_response :success
    assert_select "[role=tree]"
    assert_select "[role=treeitem]", text: /Tree Workspace/
    assert_select "[role=treeitem]", text: /Tree folder/
    assert_includes @response.body, "ID #{@root_recording.id}"
    assert_includes @response.body, "ID #{@folder_recording.id}"
    refute_includes @response.body, "rounded-xl border border-slate-200"
  end
end
