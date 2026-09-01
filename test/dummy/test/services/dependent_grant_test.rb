require_relative "../test_helper"

class DependentGrantTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @admin = create_user("dependent-admin@example.com")
    @holder = create_user("dependent-holder@example.com")
    @actor = create_user("dependent-actor@example.com")
    @other_actor = create_user("independent-actor@example.com")
    @workspace = Workspace.create!(name: "Dependent Grant Workspace")
    @recording = create_root_recording(@workspace)

    create_direct_access_recording(actor: @admin, role: :admin, parent_recording: @recording)
  end

  test "grant_access can create a dependent grant capped by a manager Access on the same root" do
    manager_grant = RecordingStudioAccessible.grant_access(
      recording: @recording,
      actor: @holder,
      role: :edit,
      manager_actor: @admin
    ).value

    result = RecordingStudioAccessible.grant_access(
      recording: @recording,
      actor: @actor,
      role: :view,
      manager_actor: @admin,
      depends_on: manager_grant
    )

    assert result.success?
    assert_equal @actor, result.value.recordable.actor
    assert_equal "view", result.value.recordable.role
    assert_equal manager_grant.id, result.value.recordable.depends_on_recording_id
    assert result.value.recordable.dependent?
    assert_equal :view, RecordingStudioAccessible.role_for(actor: @actor, recording: @recording)
    assert RecordingStudioAccessible.authorized?(actor: @actor, recording: @recording, role: :view)
  end

  test "dependent grants work for configured non-user actors" do
    manager_grant = RecordingStudioAccessible.grant_access(
      recording: @recording,
      actor: @holder,
      role: :edit,
      manager_actor: @admin
    ).value
    workspace_actor = Workspace.create!(name: "Dependent Actor Workspace")

    result = RecordingStudioAccessible.grant_access(
      recording: @recording,
      actor: workspace_actor,
      role: :view,
      manager_actor: @admin,
      depends_on: manager_grant
    )

    assert result.success?
    assert_equal workspace_actor, result.value.recordable.actor
    assert RecordingStudioAccessible.authorized?(actor: workspace_actor, recording: @recording, role: :view)
  end

  test "grant_access rejects a dependent role that exceeds the manager grant" do
    manager_grant = RecordingStudioAccessible.grant_access(
      recording: @recording,
      actor: @holder,
      role: :view,
      manager_actor: @admin
    ).value

    result = RecordingStudioAccessible.grant_access(
      recording: @recording,
      actor: @actor,
      role: :admin,
      manager_actor: @admin,
      depends_on: manager_grant
    )

    assert result.failure?
    assert_equal RecordingStudioAccessible::DependentAccess::ROLE_EXCEEDS_MESSAGE, result.error
    assert_nil RecordingStudioAccessible.role_for(actor: @actor, recording: @recording)
  end

  test "grant_access rejects a missing or trashed manager" do
    manager_grant = RecordingStudioAccessible.grant_access(
      recording: @recording,
      actor: @holder,
      role: :edit,
      manager_actor: @admin
    ).value
    manager_grant.update_column(:trashed_at, Time.current)

    trashed_result = RecordingStudioAccessible.grant_access(
      recording: @recording,
      actor: @actor,
      role: :view,
      manager_actor: @admin,
      depends_on: manager_grant
    )

    assert trashed_result.failure?
    assert_equal RecordingStudioAccessible::DependentAccess::MISSING_MANAGER_MESSAGE, trashed_result.error

    missing_result = RecordingStudioAccessible.grant_access(
      recording: @recording,
      actor: @actor,
      role: :view,
      manager_actor: @admin,
      depends_on: RecordingStudio::Recording.new(id: SecureRandom.uuid)
    )

    assert missing_result.failure?
    assert_equal RecordingStudioAccessible::DependentAccess::MISSING_MANAGER_MESSAGE, missing_result.error
  end

  test "grant_access rejects a manager that is not an Access recording on the same root" do
    other_workspace = Workspace.create!(name: "Other Dependent Root")
    other_root = create_root_recording(other_workspace)
    create_direct_access_recording(actor: @admin, role: :admin, parent_recording: other_root)
    other_grant = RecordingStudioAccessible.grant_access(
      recording: other_root,
      actor: @holder,
      role: :admin,
      manager_actor: @admin
    ).value

    off_root = RecordingStudioAccessible.grant_access(
      recording: @recording,
      actor: @actor,
      role: :view,
      manager_actor: @admin,
      depends_on: other_grant
    )

    assert off_root.failure?
    assert_equal RecordingStudioAccessible::DependentAccess::NOT_ACCESS_SAME_ROOT_MESSAGE, off_root.error

    not_access = RecordingStudioAccessible.grant_access(
      recording: @recording,
      actor: @actor,
      role: :view,
      manager_actor: @admin,
      depends_on: @recording
    )

    assert not_access.failure?
    assert_equal RecordingStudioAccessible::DependentAccess::NOT_ACCESS_SAME_ROOT_MESSAGE, not_access.error
  end

  test "authorized and role_for fail closed when the manager is trashed even if void lagged" do
    manager_grant, dependent_grant = grant_dependent_pair(manager_role: :edit, dependent_role: :view)
    RecordingStudioAccessible.grant_access(
      recording: @recording,
      actor: @other_actor,
      role: :view,
      manager_actor: @admin
    )

    manager_grant.update_column(:trashed_at, Time.current)

    assert_nil RecordingStudioAccessible.role_for(actor: @actor, recording: @recording)
    refute RecordingStudioAccessible.authorized?(actor: @actor, recording: @recording, role: :view)
    assert_equal :view, RecordingStudioAccessible.role_for(actor: @other_actor, recording: @recording)
    assert_equal dependent_grant.id, dependent_grant.reload.id
    assert_includes RecordingStudioAccessible.root_recording_ids_for(actor: @other_actor), @recording.id
    refute_includes RecordingStudioAccessible.root_recording_ids_for(actor: @actor), @recording.id
  end

  test "authorized and role_for fail closed when the manager is destroyed even if void lagged" do
    manager_grant, = grant_dependent_pair(manager_role: :edit, dependent_role: :view)
    RecordingStudio::Event.where(recording_id: manager_grant.id).delete_all
    manager_grant.delete

    assert_nil RecordingStudioAccessible.role_for(actor: @actor, recording: @recording)
    refute RecordingStudioAccessible.authorized?(actor: @actor, recording: @recording, role: :view)
  end

  test "authorized and role_for fail closed when the manager role drops below the dependent" do
    manager_grant, dependent_grant = grant_dependent_pair(manager_role: :edit, dependent_role: :edit)
    update_stored_role!(manager_grant, :view)

    assert_nil RecordingStudioAccessible.role_for(actor: @actor, recording: @recording)
    refute RecordingStudioAccessible.authorized?(actor: @actor, recording: @recording, role: :view)
    assert_equal "edit", dependent_grant.reload.recordable.role
  end

  test "void job removes a dependent grant after the manager is revoked" do
    manager_grant, dependent_grant = grant_dependent_pair(manager_role: :edit, dependent_role: :view)
    independent_grant = grant_independent

    perform_enqueued_jobs do
      result = RecordingStudioAccessible::Services::RevokeRecordingAccess.call(
        recording: @recording,
        access_recording: manager_grant,
        manager_actor: @admin
      )
      assert result.success?
    end

    assert_nil RecordingStudio::Recording.unscoped.find_by(id: dependent_grant.id)
    assert_nil RecordingStudioAccessible.role_for(actor: @actor, recording: @recording)
    assert_equal independent_grant.id, independent_grant.reload.id
    assert_equal @recording.id, independent_grant.parent_recording_id
    assert_equal :view, RecordingStudioAccessible.role_for(actor: @other_actor, recording: @recording)
  end

  test "void job removes a dependent grant after the manager is trashed" do
    manager_grant, dependent_grant = grant_dependent_pair(manager_role: :edit, dependent_role: :view)
    independent_grant = grant_independent

    perform_enqueued_jobs do
      manager_grant.update!(trashed_at: Time.current)
    end

    assert_nil RecordingStudio::Recording.unscoped.find_by(id: dependent_grant.id)
    assert_nil RecordingStudioAccessible.role_for(actor: @actor, recording: @recording)
    assert_equal independent_grant.id, independent_grant.reload.id
    assert_equal :view, RecordingStudioAccessible.role_for(actor: @other_actor, recording: @recording)
  end

  test "void job removes a dependent grant after the manager role is weakened via revise" do
    manager_grant, dependent_grant = grant_dependent_pair(manager_role: :admin, dependent_role: :edit)
    independent_grant = grant_independent
    dependent_id = dependent_grant.id
    dependent_parent_id = dependent_grant.parent_recording_id

    perform_enqueued_jobs do
      result = RecordingStudioAccessible::Services::UpdateRecordingAccess.call(
        recording: @recording,
        access_recording: manager_grant,
        role: :view,
        manager_actor: @admin
      )
      assert result.success?
    end

    assert_nil RecordingStudio::Recording.unscoped.find_by(id: dependent_id)
    assert_nil RecordingStudioAccessible.role_for(actor: @actor, recording: @recording)
    assert_equal "view", manager_grant.reload.recordable.role
    assert_equal dependent_parent_id, @recording.id
    assert_equal independent_grant.id, independent_grant.reload.id
    assert_equal :view, RecordingStudioAccessible.role_for(actor: @other_actor, recording: @recording)
  end

  test "void job voids dependents in place when the manager Access is moved" do
    manager_grant, dependent_grant = grant_dependent_pair(manager_role: :edit, dependent_role: :view)
    independent_grant = grant_independent
    folder = Folder.create!(workspace: @workspace, name: "Move Destination", summary: "Folder", position: 2)
    folder_recording = create_child_recording(recordable: folder, parent_recording: @recording)
    dependent_id = dependent_grant.id
    original_parent_id = dependent_grant.parent_recording_id

    manager_grant.update!(parent_recording: folder_recording)

    leftover = RecordingStudio::Recording.unscoped.find_by(id: dependent_id)
    if leftover
      assert_equal original_parent_id, leftover.parent_recording_id
      refute_equal folder_recording.id, leftover.parent_recording_id
    end

    perform_enqueued_jobs

    assert_nil RecordingStudio::Recording.unscoped.find_by(id: dependent_id)
    assert_nil RecordingStudio::Recording.unscoped.find_by(id: dependent_id, parent_recording_id: folder_recording.id)
    assert_equal folder_recording.id, manager_grant.reload.parent_recording_id
    assert_equal original_parent_id, independent_grant.reload.parent_recording_id
    assert RecordingStudioAccessible.authorized?(actor: @other_actor, recording: @recording, role: :view)
    assert_nil RecordingStudioAccessible.role_for(actor: @actor, recording: @recording)
    refute RecordingStudioAccessible.authorized?(actor: @actor, recording: @recording, role: :view)
  end

  test "void job is not required for fail-closed authorize after a lagged manager downgrade" do
    manager_grant, dependent_grant = grant_dependent_pair(manager_role: :admin, dependent_role: :edit)
    assert_no_enqueued_jobs only: RecordingStudioAccessible::VoidDependentAccessesJob do
      update_stored_role!(manager_grant, :view)
    end

    refute RecordingStudioAccessible.authorized?(actor: @actor, recording: @recording, role: :edit)
    assert_not_nil RecordingStudio::Recording.unscoped.find_by(id: dependent_grant.id)
  end

  test "existing non-dependent grants keep current behavior" do
    result = RecordingStudioAccessible.grant_access(
      recording: @recording,
      actor: @other_actor,
      role: :edit,
      manager_actor: @admin
    )

    assert result.success?
    refute result.value.recordable.dependent?
    assert_nil result.value.recordable.depends_on_recording_id
    assert_equal :edit, RecordingStudioAccessible.role_for(actor: @other_actor, recording: @recording)
    assert RecordingStudioAccessible.authorized?(actor: @other_actor, recording: @recording, role: :edit)
  end

  test "a dependent grant on a child is valid when the manager Access is on the same root" do
    folder = Folder.create!(workspace: @workspace, name: "Dependent Folder", summary: "Folder", position: 1)
    folder_recording = create_child_recording(recordable: folder, parent_recording: @recording)
    manager_grant = RecordingStudioAccessible.grant_access(
      recording: @recording,
      actor: @holder,
      role: :admin,
      manager_actor: @admin
    ).value

    result = RecordingStudioAccessible.grant_access(
      recording: folder_recording,
      actor: @actor,
      role: :edit,
      manager_actor: @admin,
      depends_on: manager_grant
    )

    assert result.success?
    assert_equal folder_recording.id, result.value.parent_recording_id
    assert RecordingStudioAccessible.authorized?(actor: @actor, recording: folder_recording, role: :edit)
  end

  test "updating a dependent grant cannot raise it above the manager role" do
    _manager_grant, dependent_grant = grant_dependent_pair(manager_role: :edit, dependent_role: :view)

    result = RecordingStudioAccessible::Services::UpdateRecordingAccess.call(
      recording: @recording,
      access_recording: dependent_grant,
      role: :admin,
      manager_actor: @admin
    )

    assert result.failure?
    assert_equal RecordingStudioAccessible::DependentAccess::ROLE_EXCEEDS_MESSAGE, result.error
    assert_equal "view", dependent_grant.reload.recordable.role
  end

  test "updating a dependent grant keeps depends_on and still fail-closes if the manager is trashed" do
    manager_grant, dependent_grant = grant_dependent_pair(manager_role: :edit, dependent_role: :edit)

    result = RecordingStudioAccessible::Services::UpdateRecordingAccess.call(
      recording: @recording,
      access_recording: dependent_grant,
      role: :view,
      manager_actor: @admin
    )

    assert result.success?
    revised = result.value
    assert_equal manager_grant.id, revised.recordable.depends_on_recording_id
    assert_equal "view", revised.recordable.role
    assert_not_equal dependent_grant.recordable_id, revised.recordable_id
    assert RecordingStudioAccessible.authorized?(actor: @actor, recording: @recording, role: :view)
    refute RecordingStudioAccessible.authorized?(actor: @actor, recording: @recording, role: :edit)

    manager_grant.update_column(:trashed_at, Time.current)

    refute RecordingStudioAccessible.authorized?(actor: @actor, recording: @recording, role: :view)
    assert_nil RecordingStudioAccessible.role_for(actor: @actor, recording: @recording)
    assert_equal manager_grant.id, revised.reload.recordable.depends_on_recording_id
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def grant_independent
    RecordingStudioAccessible.grant_access(
      recording: @recording,
      actor: @other_actor,
      role: :view,
      manager_actor: @admin
    ).value
  end

  def grant_dependent_pair(manager_role:, dependent_role:)
    manager_grant = RecordingStudioAccessible.grant_access(
      recording: @recording,
      actor: @holder,
      role: manager_role,
      manager_actor: @admin
    ).value
    dependent_grant = RecordingStudioAccessible.grant_access(
      recording: @recording,
      actor: @actor,
      role: dependent_role,
      manager_actor: @admin,
      depends_on: manager_grant
    ).value

    [manager_grant, dependent_grant]
  end

  def update_stored_role!(access_recording, role)
    connection = ActiveRecord::Base.connection
    stored = RecordingStudio::Access.roles.fetch(role.to_s)
    connection.execute(<<~SQL.squish)
      UPDATE recording_studio_accesses
      SET role = #{connection.quote(stored)}
      WHERE id = #{connection.quote(access_recording.recordable_id)}
    SQL
    access_recording.recordable.reload
  end
end
