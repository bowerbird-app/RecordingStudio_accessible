# frozen_string_literal: true

require_relative "../test_helper"

class AccessPathCycleTest < ActiveSupport::TestCase
  setup do
    @writer = create_user("access-path-cycle-writer@example.com")
    @actor = create_user("access-path-cycle-actor@example.com")
    Current.actor = @writer

    workspace = Workspace.create!(name: "Access Path Cycle")
    @root = create_root_recording(workspace)
    folder = Folder.create!(workspace: workspace, name: "Cycle", summary: "Cycle", position: 0)
    @folder = create_child_recording(recordable: folder, parent_recording: @root)
    page = Page.create!(folder: folder, title: "Cycle", summary: "Cycle", position: 0)
    @page = create_child_recording(recordable: page, parent_recording: @folder)
    create_direct_access_recording(actor: @actor, role: :edit, parent_recording: @folder)
  end

  test "role_for follows the parent chain when the ancestor walk hits a cycle" do
    connection = ActiveRecord::Base.connection
    connection.execute(<<~SQL.squish)
      UPDATE recording_studio_recordings
      SET parent_recording_id = #{connection.quote(@page.id)}
      WHERE id = #{connection.quote(@folder.id)}
    SQL

    page = RecordingStudio::Recording.find(@page.id)
    assert_raises(RecordingStudio::TreeWalkError) { page.ancestors }

    path = RecordingStudio::Services::AccessPath.new(recording: page).build
    assert_equal [@page.id, @folder.id], path.path_recordings.map(&:id)
    assert_equal :edit, RecordingStudioAccessible.role_for(actor: @actor, recording: page)
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end
end
