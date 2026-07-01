require_relative "../test_helper"

class RecordingStudioAccessTest < ActiveSupport::TestCase
  ACCESS_GRANT_ERROR = "Create access grants through RecordingStudioAccessible.grant_access"
  DUPLICATE_ACCESS_ERROR = "Only one direct access grant is allowed per actor under the same parent"

  test "direct access creation is blocked" do
    user = create_user("direct-access-blocked@example.com")

    assert_no_difference -> { RecordingStudio::Access.count } do
      error = assert_raises(ActiveRecord::RecordInvalid) do
        RecordingStudio::Access.create!(actor: user, role: :view)
      end

      assert_includes error.record.errors.full_messages.join, ACCESS_GRANT_ERROR
    end
  end

  test "direct access recording creation is blocked" do
    user = create_user("direct-access-recording-blocked@example.com")
    workspace = Workspace.create!(name: "Direct Access Recording Blocked Workspace")
    parent_recording = create_root_recording(workspace)
    access = RecordingStudioAccessible::AccessCreationContext.allow do
      RecordingStudio::Access.create!(actor: user, role: :view)
    end

    assert_no_difference -> { RecordingStudio::Recording.unscoped.count } do
      error = assert_raises(ActiveRecord::RecordInvalid) do
        RecordingStudio::Recording.unscoped.create!(
          root_recording_id: parent_recording.id,
          parent_recording_id: parent_recording.id,
          recordable: access
        )
      end

      assert_includes error.record.errors.full_messages.join, ACCESS_GRANT_ERROR
    end
  end

  test "recording studio record API cannot create access grants directly" do
    user = create_user("record-api-access-blocked@example.com")
    workspace = Workspace.create!(name: "Record API Access Blocked Workspace")
    parent_recording = create_root_recording(workspace)

    assert_no_difference -> { RecordingStudio::Access.count } do
      assert_no_difference -> { RecordingStudio::Recording.unscoped.count } do
        error = assert_raises(ActiveRecord::RecordInvalid) do
          parent_recording.record(
            RecordingStudio::Access,
            actor: user,
            parent_recording: parent_recording
          ) do |access|
            access.actor = user
            access.role = :view
          end
        end

        assert_includes error.record.errors.full_messages.join, ACCESS_GRANT_ERROR
      end
    end
  end

  test "duplicate direct access recordings for the same actor and parent are blocked" do
    user = create_user("duplicate-access-blocked@example.com")
    workspace = Workspace.create!(name: "Duplicate Access Recording Blocked Workspace")
    parent_recording = create_root_recording(workspace)

    create_direct_access_recording(actor: user, role: :view, parent_recording: parent_recording)

    assert_no_difference -> { RecordingStudio::Recording.unscoped.count } do
      error = assert_raises(ActiveRecord::RecordInvalid) do
        create_direct_access_recording(actor: user, role: :admin, parent_recording: parent_recording)
      end

      assert_includes error.record.errors.full_messages.join, DUPLICATE_ACCESS_ERROR
    end
  end

  test "recordable name labels non-user actors by their actor type" do
    workspace = Workspace.create!(name: "Label Workspace")
    access = RecordingStudioAccessible::AccessCreationContext.allow do
      RecordingStudio::Access.create!(actor: workspace, role: :edit)
    end

    assert_equal "Access: edit — Label Workspace (Workspace)", access.recordable_name
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end
end
