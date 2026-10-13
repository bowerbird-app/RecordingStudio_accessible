# frozen_string_literal: true

require "test_helper"

class TrashableTrashedAtParityIntegrationTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "trashable-parity-#{SecureRandom.hex(4)}@example.com", password: "Password")
    @workspace = Workspace.create!(name: "Trashable parity workspace")
    @root = create_root_recording(@workspace)
    RecordingStudioAccessible.bootstrap_owner_access!(recording: @root, actor: @user)
  end

  test "Recording exposes Trashable sibling trashed_at APIs" do
    assert_respond_to RecordingStudio::Recording, :recording_studio_trashable_active
    assert_respond_to RecordingStudio::Recording, :recording_studio_trashable_kept_sql
    assert_respond_to RecordingStudio::Recording, :recording_studio_trashable_trashed_sql
    assert_respond_to @root, :recording_studio_trashable_kept?
    assert_respond_to @root, :recording_studio_trashable_trashed?
    assert_equal "0.9.0", RecordingStudioTrashable::VERSION
  end

  test "unscoped trashable_active matches main where(trashed_at: nil) membership" do
    live_ids = RecordingStudio::Recording.unscoped.where(trashed_at: nil).order(:id).pluck(:id)
    active_ids = RecordingStudio::Recording.unscoped.recording_studio_trashable_active.order(:id).pluck(:id)

    assert_equal live_ids, active_ids
    assert_includes active_ids, @root.id
  end

  test "kept? matches main trashed_at.nil? for live and trashed rows" do
    assert @root.trashed_at.nil?
    assert @root.recording_studio_trashable_kept?
    refute @root.recording_studio_trashable_trashed?

    @root.update_column(:trashed_at, Time.current)
    @root.reload

    refute @root.trashed_at.nil?
    refute @root.recording_studio_trashable_kept?
    assert @root.recording_studio_trashable_trashed?
  end

  test "direct access query excludes trashed grants the same as main" do
    grant = RecordingStudioAccessible.access_recordings_for_actor(recording: @root, actor: @user).first
    assert grant
    assert_includes RecordingStudioAccessible::DirectAccessQuery.access_recordings_for(@root).pluck(:id), grant.id

    grant.update_column(:trashed_at, Time.current)

    refute_includes RecordingStudioAccessible::DirectAccessQuery.access_recordings_for(@root).pluck(:id), grant.id
    refute_includes RecordingStudio::Recording.unscoped.where(trashed_at: nil).where(id: grant.id).pluck(:id),
                    grant.id
  end

  test "void_recording! soft-voids a row without changing Accessible destroy semantics" do
    folder = Folder.create!(
      workspace: @workspace,
      name: "Parity folder",
      summary: "Trashable parity",
      position: 0
    )
    recording = create_child_recording(recordable: folder, parent_recording: @root)
    time = Time.utc(2026, 10, 13, 12, 0, 0)

    result = RecordingStudioTrashable.void_recording!(recording, time: time)
    recording.reload

    assert_equal recording, result
    assert_equal time.to_i, recording.trashed_at.to_i
    refute recording.recording_studio_trashable_kept?
    assert_empty RecordingStudio::Recording.unscoped.where(trashed_at: nil).where(id: recording.id)
  end

  # Host apps sometimes add `default_scope { where(trashed_at: …) }`. That leaves
  # a trashed_at predicate on ordinary relations. Trashable's
  # recording_studio_trashable_active unscopes(:trashed_at) first; main's
  # Accessible filter only adds where(trashed_at: nil). Simulate the scoped
  # base with an explicit prior predicate (same shape as a default_scope).
  test "default_scope-shaped prior trashed_at: trashable_active diverges; Accessible matches main" do
    # Prior predicate like a host default_scope that keeps only trashed rows.
    scoped = RecordingStudio::Recording.unscoped.where.not(trashed_at: nil)
    main_additive_ids = scoped.where(trashed_at: nil).order(:id).pluck(:id)
    trashable_active_ids = scoped.recording_studio_trashable_active.order(:id).pluck(:id)

    assert_empty main_additive_ids,
                 "main's additive where(trashed_at: nil) keeps the prior NOT NULL → empty"
    assert_includes trashable_active_ids, @root.id,
                    "recording_studio_trashable_active unscopes the prior trashed_at predicate"
    refute_equal main_additive_ids, trashable_active_ids

    accessible_ids = RecordingStudioAccessible::DirectAccessQuery
                     .send(:active_recordings_scope)
                     .order(:id)
                     .pluck(:id)
    main_unscoped_ids = RecordingStudio::Recording.unscoped.where(trashed_at: nil).order(:id).pluck(:id)

    assert_equal main_unscoped_ids, accessible_ids
    assert_includes accessible_ids, @root.id
  end
end


