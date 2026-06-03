require_relative "../test_helper"

class RecordingStudioAccessTest < ActiveSupport::TestCase
  ACCESS_GRANT_ERROR = "Create access grants through RecordingStudioAccessible.grant_access"

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
    parent_recording = RecordingStudio::Recording.unscoped.create!(recordable: workspace, parent_recording_id: nil)
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
    parent_recording = RecordingStudio::Recording.unscoped.create!(recordable: workspace, parent_recording_id: nil)

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

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end
end
