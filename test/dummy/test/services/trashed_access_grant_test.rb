# frozen_string_literal: true

require "test_helper"

# Trashable is registered through the dummy's query entry. void_recording! is
# Trashable's write. A grant trashed that way must not count.
class TrashedAccessGrantTest < ActiveSupport::TestCase
  setup do
    @owner = User.create!(email: "trashed-grant-owner-#{SecureRandom.hex(4)}@example.com", password: "Password")
    @member = User.create!(email: "trashed-grant-member-#{SecureRandom.hex(4)}@example.com", password: "Password")
    @workspace = Workspace.create!(name: "Trashed grant workspace")
    @root = create_root_recording(@workspace)
    folder = Folder.create!(workspace: @workspace, name: "Trashed grant folder", summary: "Folder", position: 0)
    @folder = create_child_recording(recordable: folder, parent_recording: @root)

    bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(recording: @root, actor: @owner)
    assert bootstrap.success?, bootstrap.error.to_s

    granted = RecordingStudioAccessible.grant_access(
      recording: @root, actor: @member, role: :view, manager_actor: @owner
    )
    assert granted.success?, granted.error.to_s
    @grant = granted.value
  end

  test "a grant trashed through Trashable does not authorize" do
    assert_equal "1.0.1", RecordingStudioTrashable::VERSION
    refute defined?(RecordingStudioTrashable::Engine)
    assert_includes RecordingStudio.kept_sql, "trashed_at IS NULL"
    assert @grant.kept?

    assert_equal :view, RecordingStudioAccessible.role_for(actor: @member, recording: @root)
    assert_equal :view, RecordingStudioAccessible.role_for(actor: @member, recording: @folder)
    assert RecordingStudioAccessible.authorized?(actor: @member, recording: @root, role: :view)
    assert_includes authorized_ids, @root.id
    assert_includes authorized_ids, @folder.id
    assert_includes authorized_recording_ids, @root.id
    assert_includes authorized_recording_ids, @folder.id
    assert_includes grant_ids, @grant.id

    RecordingStudioTrashable.void_recording!(@grant)
    @grant.reload

    refute @grant.trashed_at.nil?
    refute @grant.kept?
    assert_nil RecordingStudioAccessible.role_for(actor: @member, recording: @root)
    assert_nil RecordingStudioAccessible.role_for(actor: @member, recording: @folder)
    refute RecordingStudioAccessible.authorized?(actor: @member, recording: @root, role: :view)
    refute RecordingStudioAccessible.authorized?(actor: @member, recording: @folder, role: :view)
    refute_includes authorized_ids, @root.id
    refute_includes authorized_ids, @folder.id
    refute_includes authorized_recording_ids, @root.id
    refute_includes authorized_recording_ids, @folder.id
    refute_includes grant_ids, @grant.id

    assert_equal :admin, RecordingStudioAccessible.role_for(actor: @owner, recording: @root)
    assert_includes RecordingStudioAccessible.access_grants_for(actor: @owner).pluck(:id), owner_grant_id
  end

  private

  def authorized_ids
    RecordingStudioAccessible.authorized_recording_ids(actor: @member, root: @root).pluck(:id)
  end

  def authorized_recording_ids
    RecordingStudioAccessible.authorized_recordings(actor: @member, root: @root).pluck(:id)
  end

  def grant_ids
    RecordingStudioAccessible.access_grants_for(actor: @member).pluck(:id)
  end

  def owner_grant_id
    RecordingStudioAccessible.access_recordings_for_actor(recording: @root, actor: @owner).pick(:id)
  end
end
