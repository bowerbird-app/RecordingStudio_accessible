require_relative "../test_helper"

class SharedRootAccessTest < ActiveSupport::TestCase
  setup do
    @manager = create_user("shared-root-manager@example.com")
    @user = create_user("shared-root-user@example.com")

    @message_root = MessageRoot.create!(name: "Shared Messages Root")
    @message_root_recording = create_root_recording(@message_root)
    @message_group = MessageGroup.create!(
      message_root: @message_root,
      name: "Shared group",
      summary: "Group under shared root",
      position: 0
    )
    @message_group_recording = create_child_recording(
      recordable: @message_group,
      parent_recording: @message_root_recording
    )

    @workspace = Workspace.create!(name: "Shared Root Workspace")
    @workspace_recording = create_root_recording(@workspace)

    create_legacy_shared_root_access(actor: @manager, role: :admin)
    create_direct_access_recording(actor: @manager, role: :admin, parent_recording: @message_group_recording)
    create_direct_access_recording(actor: @manager, role: :admin, parent_recording: @workspace_recording)
  end

  test "grant_access rejects shared root targets with shared-root-specific message" do
    result = RecordingStudioAccessible.grant_access(
      recording: @message_root_recording,
      actor: @user,
      role: :view,
      manager_actor: @manager
    )

    assert result.failure?
    assert_equal RecordingStudioAccessible::SharedRootAccess::GRANT_DENIED_MESSAGE, result.error
  end

  test "grant_access still succeeds on descendants under a shared root" do
    result = RecordingStudioAccessible.grant_access(
      recording: @message_group_recording,
      actor: @user,
      role: :view,
      manager_actor: @manager
    )

    assert result.success?
    assert_equal @user, result.value.recordable.actor
    assert_equal @message_group_recording.id, result.value.parent_recording_id
    assert RecordingStudioAccessible.authorized?(actor: @user, recording: @message_group_recording, role: :view)
  end

  test "update_access rejects shared root targets" do
    legacy_access = create_legacy_shared_root_access(actor: @user, role: :view)

    result = RecordingStudioAccessible::Services::UpdateRecordingAccess.call(
      recording: @message_root_recording,
      access_recording: legacy_access,
      role: :edit,
      manager_actor: @manager
    )

    assert result.failure?
    assert_equal RecordingStudioAccessible::SharedRootAccess::GRANT_DENIED_MESSAGE, result.error
  end

  test "revoke_access still allows removing legacy grants on shared roots" do
    legacy_access = create_legacy_shared_root_access(actor: @user, role: :view)

    result = RecordingStudioAccessible::Services::RevokeRecordingAccess.call(
      recording: @message_root_recording,
      access_recording: legacy_access,
      manager_actor: @manager
    )

    assert result.success?
    assert_nil RecordingStudio::Recording.unscoped.find_by(id: legacy_access.id)
  end

  test "root listing helpers exclude shared roots but keep owned workspace roots" do
    grant_on_group = RecordingStudioAccessible.grant_access(
      recording: @message_group_recording,
      actor: @user,
      role: :view,
      manager_actor: @manager
    )
    assert grant_on_group.success?

    grant_on_workspace = RecordingStudioAccessible.grant_access(
      recording: @workspace_recording,
      actor: @user,
      role: :view,
      manager_actor: @manager
    )
    assert grant_on_workspace.success?

    assert_equal [@workspace_recording], RecordingStudioAccessible.root_recordings_for(actor: @user)
    assert_equal [@workspace_recording.id], RecordingStudioAccessible.root_recording_ids_for(actor: @user)
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def create_legacy_shared_root_access(actor:, role:)
    connection = ActiveRecord::Base.connection
    access_id = SecureRandom.uuid
    recording_id = SecureRandom.uuid
    now = Time.current.utc.iso8601(6)
    stored_role = RecordingStudio::Access.roles.fetch(role.to_s)

    connection.exec_insert(<<~SQL.squish, "SQL", [])
      INSERT INTO recording_studio_accesses
        (id, actor_type, actor_id, role, created_at)
      VALUES
        (#{connection.quote(access_id)}, #{connection.quote(RecordingStudioAccessible::ActorType.for(actor))},
         #{connection.quote(actor.id)}, #{connection.quote(stored_role)}, #{connection.quote(now)})
    SQL
    connection.exec_insert(<<~SQL.squish, "SQL", [])
      INSERT INTO recording_studio_recordings
        (id, recordable_type, recordable_id, parent_recording_id, root_recording_id, created_at, updated_at)
      VALUES
        (#{connection.quote(recording_id)}, 'RecordingStudio::Access', #{connection.quote(access_id)},
         #{connection.quote(@message_root_recording.id)}, #{connection.quote(@message_root_recording.id)},
         #{connection.quote(now)}, #{connection.quote(now)})
    SQL
    RecordingStudio::Recording.unscoped.find(recording_id)
  end
end
