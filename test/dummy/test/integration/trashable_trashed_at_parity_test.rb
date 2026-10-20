# frozen_string_literal: true

require "test_helper"

class TrashableTrashedAtParityIntegrationTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "trashable-parity-#{SecureRandom.hex(4)}@example.com", password: "Password")
    @workspace = Workspace.create!(name: "Trashable parity workspace")
    @root = create_root_recording(@workspace)
    RecordingStudioAccessible.bootstrap_owner_access!(recording: @root, actor: @user)
  end

  test "query helpers are available without Trashable engine" do
    assert_equal "0.11.2", RecordingStudioTrashable::VERSION
    refute defined?(RecordingStudioTrashable::Engine)
    assert_respond_to RecordingStudio::Recording, :recording_studio_trashable_kept_sql
    assert_respond_to @root, :recording_studio_trashable_kept?
    refute_respond_to @root, :recording_studio_trashable_trash!
    refute_respond_to @root, :recording_studio_trashable_restore!
    refute_respond_to @root, :recording_studio_trashable_purge!
  end

  test "kept_sql membership matches main where(trashed_at: nil) on unscoped" do
    live_ids = RecordingStudio::Recording.unscoped.where(trashed_at: nil).order(:id).pluck(:id)
    kept_ids = RecordingStudio::Recording.unscoped
                                         .where(RecordingStudio::Recording.recording_studio_trashable_kept_sql)
                                         .order(:id)
                                         .pluck(:id)

    assert_equal live_ids, kept_ids
    assert_includes kept_ids, @root.id
  end

  test "kept? matches main trashed_at.nil? for live and trashed rows" do
    assert @root.trashed_at.nil?
    assert @root.recording_studio_trashable_kept?

    @root.update_column(:trashed_at, Time.current)
    @root.reload

    refute @root.trashed_at.nil?
    refute @root.recording_studio_trashable_kept?
  end

  test "direct access query excludes trashed grants the same as main" do
    grant = RecordingStudioAccessible.access_recordings_for_actor(recording: @root, actor: @user).first
    assert grant
    assert_includes RecordingStudioAccessible::DirectAccessQuery.access_recordings_for(@root).pluck(:id), grant.id

    grant.update_column(:trashed_at, Time.current)

    refute_includes RecordingStudioAccessible::DirectAccessQuery.access_recordings_for(@root).pluck(:id), grant.id
  end

  # Real call sites under a host default_scope shaped like where.not(trashed_at: nil).
  # Accessible starts from unscoped + additive kept_sql (same as main's
  # where(trashed_at: nil)). recording_studio_trashable_active would unscope and diverge.
  test "call sites under default_scope where.not(trashed_at: nil) match main additive filter" do
    previous_scopes = RecordingStudio::Recording.default_scopes.dup
    RecordingStudio::Recording.send(:default_scope, -> { where.not(trashed_at: nil) })

    begin
      scoped = RecordingStudio::Recording.all
      main_additive_ids = scoped.where(trashed_at: nil).order(:id).pluck(:id)
      kept_sql_ids = scoped.where(RecordingStudio::Recording.recording_studio_trashable_kept_sql)
                           .order(:id)
                           .pluck(:id)
      trashable_active_ids = scoped.recording_studio_trashable_active.order(:id).pluck(:id)

      assert_empty main_additive_ids
      assert_equal main_additive_ids, kept_sql_ids
      assert_includes trashable_active_ids, @root.id,
                      "recording_studio_trashable_active unscopes the default_scope trashed_at predicate"
      refute_equal main_additive_ids, trashable_active_ids

      accessible_ids = RecordingStudioAccessible::DirectAccessQuery
                       .send(:active_recordings_scope)
                       .order(:id)
                       .pluck(:id)
      audience_ids = RecordingStudioAccessible::AudienceQuery
                     .send(:live_recordings)
                     .order(:id)
                     .pluck(:id)
      main_unscoped_ids = RecordingStudio::Recording.unscoped.where(trashed_at: nil).order(:id).pluck(:id)

      assert_equal main_unscoped_ids, accessible_ids
      assert_equal main_unscoped_ids, audience_ids
      assert_includes accessible_ids, @root.id
    ensure
      RecordingStudio::Recording.default_scopes.replace(previous_scopes)
    end
  end
end
