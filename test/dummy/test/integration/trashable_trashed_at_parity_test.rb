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
    assert_equal "0.16.0", RecordingStudioTrashable::VERSION
    refute defined?(RecordingStudioTrashable::Engine)
    assert_respond_to RecordingStudio::Recording, :kept
    assert_respond_to @root, :recording_studio_trashable_kept?
    refute_respond_to RecordingStudio::Recording, :recording_studio_trashable_active
    # Dummy-only bridge for recording_studio_api 0.23.3. The gem does not define this.
    assert_equal RecordingStudio.kept_sql, RecordingStudio::Recording.recording_studio_trashable_kept_sql
    assert_equal RecordingStudio.kept_sql("child"),
                 RecordingStudio::Recording.recording_studio_trashable_kept_sql("child")
    refute_respond_to @root, :recording_studio_trashable_trash!
    refute_respond_to @root, :recording_studio_trashable_restore!
    refute_respond_to @root, :recording_studio_trashable_purge!
  end

  test "kept membership matches where(trashed_at: nil) on unscoped" do
    live_ids = RecordingStudio::Recording.unscoped.where(trashed_at: nil).order(:id).pluck(:id)
    kept_ids = RecordingStudio::Recording.unscoped.kept.order(:id).pluck(:id)
    sql_ids = RecordingStudio::Recording.unscoped
                                        .where(Arel.sql(RecordingStudio.kept_sql))
                                        .order(:id)
                                        .pluck(:id)

    assert_equal live_ids, kept_ids
    assert_equal live_ids, sql_ids
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

  # Accessible starts from unscoped.kept. That adds the filter without
  # unscope, so a host default_scope of where.not(trashed_at: nil) does not
  # leak into these queries.
  test "call sites ignore a default_scope that keeps only trashed rows" do
    previous_scopes = RecordingStudio::Recording.default_scopes.dup
    RecordingStudio::Recording.send(:default_scope, -> { where.not(trashed_at: nil) })

    begin
      assert_empty RecordingStudio::Recording.kept.order(:id).pluck(:id)

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

  test "kept is a no-op when the trashable filter is not registered" do
    grant = RecordingStudioAccessible.access_recordings_for_actor(recording: @root, actor: @user).first
    grant.update_column(:trashed_at, Time.current)
    RecordingStudio.unregister_recording_filter(:trashable)

    assert_equal "1=1", RecordingStudio.kept_sql
    assert_includes RecordingStudio::Recording.unscoped.kept.pluck(:id), grant.id
    assert_includes RecordingStudioAccessible::DirectAccessQuery.access_recordings_for(@root).pluck(:id), grant.id
    assert RecordingStudioAccessible.authorized?(actor: @user, recording: @root, role: :admin)
  ensure
    RecordingStudioTrashable::RecordingFilter.register!
  end
end
