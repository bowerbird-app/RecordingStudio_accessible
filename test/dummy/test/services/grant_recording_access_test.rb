require_relative "../test_helper"

class GrantRecordingAccessTest < ActiveSupport::TestCase
  setup do
    @manager_actor = create_user("grant-manager@example.com")
    @user = create_user("grant-user@example.com")
    @workspace = Workspace.create!(name: "Grant Recording Access Workspace")
    @recording = create_root_recording(@workspace)

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

  test "service creates access grants under opted in folder recordings" do
    folder = Folder.create!(workspace: @workspace, name: "Grant Folder", summary: "Folder", position: 1)
    folder_recording = create_child_recording(recordable: folder, parent_recording: @recording)

    result = RecordingStudioAccessible.grant_access(
      recording: folder_recording,
      actor: @user,
      role: :view,
      manager_actor: @manager_actor
    )

    assert result.success?
    assert_equal folder_recording.id, result.value.parent_recording_id
    assert_equal @recording.id, RecordingStudio.root_recording_id_for(result.value)
  end

  test "service rejects access grants under recordables that did not opt in" do
    folder = Folder.create!(workspace: @workspace, name: "Page Parent", summary: "Folder", position: 2)
    folder_recording = create_child_recording(recordable: folder, parent_recording: @recording)
    page = Page.create!(folder: folder, title: "Closed Page", summary: "Page", position: 0)
    page_recording = create_child_recording(recordable: page, parent_recording: folder_recording)

    assert_no_difference -> { RecordingStudio::Access.count } do
      assert_no_difference -> { RecordingStudio::Recording.unscoped.count } do
        @result = RecordingStudioAccessible.grant_access(
          recording: page_recording,
          actor: @user,
          role: :view,
          manager_actor: @manager_actor
        )
      end
    end

    assert @result.failure?
    assert_equal "Direct access is not enabled for this recording", @result.error
  end

  test "granting access requires an actor" do
    assert_no_difference -> { RecordingStudio::Access.count } do
      assert_no_difference -> { RecordingStudio::Recording.unscoped.count } do
        @result = RecordingStudioAccessible.grant_access(
          recording: @recording,
          actor: nil,
          role: :view,
          manager_actor: @manager_actor
        )
      end
    end

    assert @result.failure?
    assert_equal "Actor is required", @result.error
  end

  test "granting access deduplicates existing direct grants for the same actor" do
    stale_recording = create_legacy_direct_access_recording(@user, :view, @recording)
    other_user = create_user("grant-other-user@example.com")
    second_recording = create_legacy_direct_access_recording(other_user, :admin, @recording)
    connection = ActiveRecord::Base.connection
    connection.execute(<<~SQL.squish)
      UPDATE recording_studio_accesses
      SET actor_type = #{connection.quote(@user.class.base_class.name)}, actor_id = #{connection.quote(@user.id)}
      WHERE id = #{connection.quote(second_recording.recordable_id)}
    SQL

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

  def create_legacy_direct_access_recording(user, role, parent_recording)
    create_direct_access_recording(actor: user, role: role, parent_recording: parent_recording)
  end

  def direct_access_recordings_for(user)
    RecordingStudioAccessible::DirectAccessQuery.access_recordings_for_actor(recording: @recording, actor: user)
  end
end
