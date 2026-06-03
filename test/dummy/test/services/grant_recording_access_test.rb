require_relative "../test_helper"

class GrantRecordingAccessTest < ActiveSupport::TestCase
  setup do
    @manager_actor = create_user("grant-manager@example.com")
    @user = create_user("grant-user@example.com")
    @workspace = Workspace.create!(name: "Grant Recording Access Workspace")
    @recording = RecordingStudio::Recording.unscoped.create!(recordable: @workspace, parent_recording_id: nil)

    create_legacy_direct_access_recording(@manager_actor, :admin, @recording)
  end

  test "service creates access grants internally" do
    assert_difference -> { RecordingStudio::Access.count }, 1 do
      assert_difference -> { RecordingStudio::Recording.unscoped.count }, 1 do
        @result = RecordingStudioAccessible::Services::GrantRecordingAccess.call(
          recording: @recording,
          actor: @user,
          role: :view,
          manager_actor: @manager_actor
        )
      end
    end

    assert @result.success?
    refute @result.failure?
    assert_kind_of RecordingStudio::Recording, @result.value
    assert_equal @user, @result.value.recordable.actor
    assert_equal "view", @result.value.recordable.role
    assert_equal @recording.id, @result.value.parent_recording_id
  end

  test "public facade delegates to the grant service" do
    result = RecordingStudioAccessible.grant_access(
      recording: @recording,
      actor: @user,
      role: :edit,
      manager_actor: @manager_actor
    )

    assert result.success?
    assert_kind_of RecordingStudio::Recording, result.value
    assert_equal @user, result.value.recordable.actor
    assert_equal "edit", result.value.recordable.role
    assert_equal @recording.id, result.value.parent_recording_id
  end

  test "granting access deduplicates existing direct grants for the same actor" do
    stale_recording = create_legacy_direct_access_recording(@user, :view, @recording)
    create_legacy_direct_access_recording(@user, :admin, @recording)

    assert_equal 2, direct_access_recordings_for(@user).count

    result = RecordingStudioAccessible::Services::GrantRecordingAccess.call(
      recording: @recording,
      actor: @user,
      role: :edit,
      manager_actor: @manager_actor
    )

    assert result.success?

    remaining_recordings = direct_access_recordings_for(@user)
    assert_equal 1, remaining_recordings.count
    assert_equal "edit", remaining_recordings.first.recordable.role
    assert_nil RecordingStudio::Recording.unscoped.find_by(id: stale_recording.id)
    assert_nil RecordingStudio::Access.find_by(id: stale_recording.recordable_id)
  end

  test "granting access can revise an existing direct grant" do
    original = RecordingStudioAccessible.grant_access(
      recording: @recording,
      actor: @user,
      role: :view,
      manager_actor: @manager_actor
    )

    assert original.success?

    result = RecordingStudioAccessible.grant_access(
      recording: @recording,
      actor: @user,
      role: :edit,
      manager_actor: @manager_actor
    )

    assert result.success?
    assert_equal 1, direct_access_recordings_for(@user).count
    assert_equal "edit", result.value.recordable.role
  end

  test "update service can revise an existing direct grant" do
    access_recording = RecordingStudioAccessible.grant_access(
      recording: @recording,
      actor: @user,
      role: :view,
      manager_actor: @manager_actor
    ).value

    result = RecordingStudioAccessible::Services::UpdateRecordingAccess.call(
      recording: @recording,
      access_recording: access_recording,
      role: :admin,
      manager_actor: @manager_actor
    )

    assert result.success?
    assert_equal "admin", result.value.recordable.role
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def create_legacy_direct_access_recording(user, role, parent_recording, root_recording = parent_recording)
    access = RecordingStudioAccessible::AccessCreationContext.allow do
      RecordingStudio::Access.create!(actor: user, role: role)
    end

    RecordingStudio::Recording.unscoped.create!(
      root_recording_id: root_recording.id,
      parent_recording_id: parent_recording.id,
      recordable: access
    )
  end

  def direct_access_recordings_for(user)
    RecordingStudioAccessible::DirectAccessQuery.access_recordings_for_actor(recording: @recording, actor: user)
  end
end
