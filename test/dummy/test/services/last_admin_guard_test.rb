# frozen_string_literal: true

require_relative "../test_helper"
require "active_job/test_helper"

class LastAdminGuardTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  LAST_ADMIN_MESSAGE = "Add another admin before removing the last one."

  setup do
    @admin = create_user("last-admin@example.com")
    @other_admin = create_user("last-admin-other@example.com")
    @viewer = create_user("last-admin-viewer@example.com")
    @workspace = Workspace.create!(name: "Last Admin Workspace")
    @recording = create_root_recording(@workspace)
  end

  test "revoking the last direct admin is denied and the grant stays" do
    access = grant!(@admin, :admin)

    result = RecordingStudioAccessible.revoke_access(
      recording: @recording,
      access_recording: access,
      manager_actor: @admin
    )

    assert_last_admin_failure(result)
    assert_equal access.id, RecordingStudio::Recording.unscoped.find_by(id: access.id).id
    assert RecordingStudioAccessible.authorized?(actor: @admin, recording: @recording, role: :admin)
  end

  test "revoking a non-last direct admin is allowed" do
    grant!(@admin, :admin)
    other = grant!(@other_admin, :admin)

    result = RecordingStudioAccessible.revoke_access(
      recording: @recording,
      access_recording: other,
      manager_actor: @admin
    )

    assert result.success?
    assert_nil RecordingStudio::Recording.unscoped.find_by(id: other.id)
    assert RecordingStudioAccessible.authorized?(actor: @admin, recording: @recording, role: :admin)
  end

  test "inherited admin counts so a child revoke is allowed" do
    grant!(@admin, :admin)
    folder = Folder.create!(workspace: @workspace, name: "Child", summary: "Folder", position: 0)
    child = create_child_recording(recordable: folder, parent_recording: @recording)
    child_admin = grant!(@other_admin, :admin, child)

    result = RecordingStudioAccessible.revoke_access(
      recording: child,
      access_recording: child_admin,
      manager_actor: @admin
    )

    assert result.success?
    assert RecordingStudioAccessible.authorized?(actor: @admin, recording: child, role: :admin)
    refute RecordingStudioAccessible.authorized?(actor: @other_admin, recording: child, role: :admin)
  end

  test "self-removal of the last admin is denied" do
    access = grant!(@admin, :admin)

    result = RecordingStudioAccessible.revoke_access(
      recording: @recording,
      access_recording: access,
      manager_actor: @admin
    )

    assert_last_admin_failure(result)
    assert RecordingStudioAccessible.authorized?(actor: @admin, recording: @recording, role: :admin)
  end

  test "self-removal is allowed when another admin remains" do
    own = grant!(@admin, :admin)
    grant!(@other_admin, :admin)

    result = RecordingStudioAccessible.revoke_access(
      recording: @recording,
      access_recording: own,
      manager_actor: @admin
    )

    assert result.success?
    assert RecordingStudioAccessible.authorized?(actor: @other_admin, recording: @recording, role: :admin)
  end

  test "downgrading the last admin is denied" do
    access = grant!(@admin, :admin)

    result = RecordingStudioAccessible.update_access(
      recording: @recording,
      access_recording: access,
      role: :view,
      manager_actor: @admin
    )

    assert result.failure?
    assert_equal "Add another admin before changing the last admin's role.", result.error
    assert_kind_of RecordingStudioAccessible::LastAdminError, result.errors.first
    assert_equal :admin, RecordingStudioAccessible.role_for(actor: @admin, recording: @recording)
  end

  test "downgrading a non-last admin is allowed" do
    grant!(@admin, :admin)
    other = grant!(@other_admin, :admin)

    result = RecordingStudioAccessible.update_access(
      recording: @recording,
      access_recording: other,
      role: :view,
      manager_actor: @admin
    )

    assert result.success?
    assert_equal :view, RecordingStudioAccessible.role_for(actor: @other_admin, recording: @recording)
    assert RecordingStudioAccessible.authorized?(actor: @admin, recording: @recording, role: :admin)
  end

  test "a dependent cascade that would remove the last admin is blocked atomically" do
    folder_a = Folder.create!(workspace: @workspace, name: "Folder A", summary: "A", position: 1)
    folder_b = Folder.create!(workspace: @workspace, name: "Folder B", summary: "B", position: 2)
    recording_a = create_child_recording(recordable: folder_a, parent_recording: @recording)
    recording_b = create_child_recording(recordable: folder_b, parent_recording: @recording)
    staying = grant!(@admin, :admin, recording_a)
    manager = grant!(@other_admin, :admin, recording_a)
    dependent = RecordingStudioAccessible::AccessCreationContext.allow do
      RecordingStudio.root_recording_or_self(recording_b).record(
        RecordingStudio::Access,
        parent_recording: recording_b
      ) do |access|
        access.actor = @viewer
        access.role = :admin
        access.depends_on_recording_id = manager.id
      end
    end

    result = RecordingStudioAccessible.revoke_access(
      recording: recording_a,
      access_recording: manager,
      manager_actor: @admin
    )

    assert_last_admin_failure(result)
    assert_equal manager.id, RecordingStudio::Recording.unscoped.find_by(id: manager.id).id
    assert_equal dependent.id, RecordingStudio::Recording.unscoped.find_by(id: dependent.id).id
    assert RecordingStudioAccessible.authorized?(actor: @other_admin, recording: recording_a, role: :admin)
    assert RecordingStudioAccessible.authorized?(actor: @viewer, recording: recording_b, role: :admin)
    assert_equal staying.id, RecordingStudio::Recording.unscoped.find_by(id: staying.id).id
  end

  test "a trashed admin grant is not counted" do
    live = grant!(@admin, :admin)
    trashed = grant!(@other_admin, :admin)
    trashed.update_column(:trashed_at, Time.current)

    result = RecordingStudioAccessible.revoke_access(
      recording: @recording,
      access_recording: live,
      manager_actor: @admin
    )

    assert_last_admin_failure(result)
    assert RecordingStudioAccessible.authorized?(actor: @admin, recording: @recording, role: :admin)
  end

  test "a pending invitation is not counted" do
    access = grant!(@admin, :admin)
    invite = RecordingStudioAccessible.invite_access(
      recording: @recording,
      email: "pending-admin@example.com",
      role: :admin,
      manager_actor: @admin
    )
    assert invite.success?

    result = RecordingStudioAccessible.revoke_access(
      recording: @recording,
      access_recording: access,
      manager_actor: @admin
    )

    assert_last_admin_failure(result)
    assert RecordingStudioAccessible::AccessInvitation.exists?(email: "pending-admin@example.com")
  end

  test "revoke_access_invitation is never blocked by the last-admin guard" do
    grant!(@admin, :admin)
    RecordingStudioAccessible.invite_access(
      recording: @recording,
      email: "invite-only-admin@example.com",
      role: :admin,
      manager_actor: @admin
    )

    result = RecordingStudioAccessible.revoke_access_invitation(
      invitation: RecordingStudioAccessible::AccessInvitation.find_by!(email: "invite-only-admin@example.com"),
      manager_actor: @admin
    )

    assert result.success?
    assert RecordingStudioAccessible.authorized?(actor: @admin, recording: @recording, role: :admin)
  end

  test "allow_last_admin_removal opts out of the guard" do
    access = grant!(@admin, :admin)

    result = RecordingStudioAccessible.revoke_access(
      recording: @recording,
      access_recording: access,
      manager_actor: @admin,
      allow_last_admin_removal: true
    )

    assert result.success?
    assert_nil RecordingStudio::Recording.unscoped.find_by(id: access.id)
    refute RecordingStudioAccessible.authorized?(actor: @admin, recording: @recording, role: :admin)
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def grant!(actor, role, recording = @recording)
    create_direct_access_recording(actor: actor, role: role, parent_recording: recording)
  end

  def assert_last_admin_failure(result)
    assert result.failure?
    assert_equal LAST_ADMIN_MESSAGE, result.error
    assert_kind_of RecordingStudioAccessible::LastAdminError, result.errors.first
  end
end

class LastAdminGuardConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  test "concurrent last-admin removals leave at least one admin" do
    admin = create_user("last-admin-race-a@example.com")
    other_admin = create_user("last-admin-race-b@example.com")
    workspace = Workspace.create!(name: "Last Admin Race Workspace")
    recording = create_root_recording(workspace)
    first = create_direct_access_recording(actor: admin, role: :admin, parent_recording: recording)
    second = create_direct_access_recording(actor: other_admin, role: :admin, parent_recording: recording)
    recording_id = recording.id
    first_id = first.id
    second_id = second.id
    admin_id = admin.id
    other_id = other_admin.id

    results = Queue.new
    errors = Queue.new
    barrier = Queue.new

    threads = [
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          barrier.pop
          results << RecordingStudioAccessible.revoke_access(
            recording: RecordingStudio::Recording.unscoped.find(recording_id),
            access_recording: RecordingStudio::Recording.unscoped.find(first_id),
            manager_actor: User.find(admin_id)
          )
        end
      rescue StandardError => e
        errors << e
      end,
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          barrier.pop
          results << RecordingStudioAccessible.revoke_access(
            recording: RecordingStudio::Recording.unscoped.find(recording_id),
            access_recording: RecordingStudio::Recording.unscoped.find(second_id),
            manager_actor: User.find(other_id)
          )
        end
      rescue StandardError => e
        errors << e
      end
    ]

    2.times { barrier << true }
    threads.each(&:join)

    thread_errors = Array.new(errors.size) { errors.pop }
    collected = Array.new(results.size) { results.pop }
    assert_empty thread_errors, thread_errors.map(&:message).join("\n")
    assert_equal 2, collected.size
    assert_equal 1, collected.count(&:success?)
    assert_equal 1, collected.count(&:failure?)
    assert RecordingStudioAccessible::LastAdminGuard.administered?(
      RecordingStudio::Recording.unscoped.find(recording_id)
    )
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end
end
