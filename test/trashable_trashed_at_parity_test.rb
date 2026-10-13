# frozen_string_literal: true

require "test_helper"

# Proves Accessible routes soft-trash filtering through Recording Studio Trashable
# instead of raw `where(trashed_at: nil)` / `trashed_at.nil?`, with the same
# column-existence / respond_to guards as main.
class TrashableTrashedAtParityTest < Minitest::Test
  class RelationSpy
    attr_reader :wheres, :trashable_active_calls

    def initialize
      @wheres = []
      @trashable_active_calls = 0
    end

    def where(*args)
      @wheres << args
      self
    end

    def recording_studio_trashable_active
      @trashable_active_calls += 1
      where(trashed_at: nil)
    end

    def joins(*)
      self
    end

    def order(*)
      self
    end

    def includes(*)
      self
    end

    def select(*)
      self
    end
  end

  RecordingStub = Struct.new(:trashed_at, keyword_init: true) do
    def recording_studio_trashable_kept?
      !trashed_at.present?
    end
  end

  class LifecycleHarness
    include RecordingStudioAccessible::Services::AccessRecordLifecycle
  end

  def setup
    ensure_recording_class!
    @relation = RelationSpy.new
  end

  def teardown
    RecordingStudio.send(:remove_const, :Recording) if @created_recording_class
  end

  def test_trashable_gem_is_loaded
    assert defined?(RecordingStudioTrashable)
    assert_equal "0.9.0", RecordingStudioTrashable::VERSION
  end

  def test_direct_access_query_uses_trashable_active_when_trashed_at_exists
    with_unscoped_and_column(true) do
      RecordingStudioAccessible::DirectAccessQuery.send(:active_recordings_scope)
    end

    assert_equal 1, @relation.trashable_active_calls
    assert_includes @relation.wheres, [{ trashed_at: nil }]
  end

  def test_direct_access_query_skips_trashable_active_when_column_missing
    with_unscoped_and_column(false) do
      assert_same @relation, RecordingStudioAccessible::DirectAccessQuery.send(:active_recordings_scope)
    end

    assert_equal 0, @relation.trashable_active_calls
    assert_empty @relation.wheres
  end

  def test_audience_query_uses_trashable_active_when_trashed_at_exists
    with_unscoped_and_column(true) do
      RecordingStudioAccessible::AudienceQuery.send(:live_recordings)
    end

    assert_equal 1, @relation.trashable_active_calls
    assert_includes @relation.wheres, [{ trashed_at: nil }]
  end

  def test_authorization_class_methods_use_trashable_active_when_trashed_at_exists
    host = Object.new
    host.extend(RecordingStudioAccessible::AuthorizationClassMethods)

    with_unscoped_and_column(true) do
      host.send(:active_recordings_scope)
    end

    assert_equal 1, @relation.trashable_active_calls
    assert_includes @relation.wheres, [{ trashed_at: nil }]
  end

  def test_access_grant_integrity_uses_trashable_active_when_trashed_at_exists
    service = RecordingStudioAccessible::Services::AccessGrantIntegrity.new

    with_unscoped_and_column(true) do
      service.send(:active_access_recordings)
    end

    assert_equal 1, @relation.trashable_active_calls
    assert_includes @relation.wheres, [{ trashed_at: nil }]
  end

  def test_lifecycle_active_recording_delegates_to_trashable_kept
    harness = LifecycleHarness.new

    assert harness.send(:active_recording?, RecordingStub.new(trashed_at: nil))
    refute harness.send(:active_recording?, RecordingStub.new(trashed_at: Time.now))
  end

  def test_lifecycle_active_recording_passes_without_trashed_at
    harness = LifecycleHarness.new
    plain = Object.new

    assert harness.send(:active_recording?, plain)
  end

  def test_dependent_access_active_recording_delegates_to_trashable_kept
    assert RecordingStudioAccessible::DependentAccess.send(:active_recording?,
                                                           RecordingStub.new(trashed_at: nil))
    refute RecordingStudioAccessible::DependentAccess.send(:active_recording?,
                                                           RecordingStub.new(trashed_at: Time.now))
    refute RecordingStudioAccessible::DependentAccess.send(:active_recording?, nil)
  end

  def test_kept_predicate_matches_main_nil_check_for_datetime_values
    kept = RecordingStub.new(trashed_at: nil)
    trashed = RecordingStub.new(trashed_at: Time.utc(2026, 10, 13))

    assert_equal kept.trashed_at.nil?, kept.recording_studio_trashable_kept?
    assert_equal trashed.trashed_at.nil?, trashed.recording_studio_trashable_kept?
  end

  def test_accessible_does_not_soft_void_on_destroy_path
    source = File.read(
      File.expand_path("../lib/recording_studio_accessible/services/access_record_lifecycle.rb", __dir__)
    )

    assert_includes source, "access_recording.destroy!"
    refute_includes source, "void_recording!"
    refute_includes source, "recording_studio_trashable_void!"
  end

  private

  def with_unscoped_and_column(column_present, &block)
    columns = column_present ? ["trashed_at"] : []
    RecordingStudio::Recording.stub(:unscoped, @relation) do
      RecordingStudio::Recording.stub(:column_names, columns, &block)
    end
  end

  def ensure_recording_class!
    return if RecordingStudio.const_defined?(:Recording, false)

    @created_recording_class = true
    RecordingStudio.const_set(:Recording, Class.new do
      def self.unscoped = nil
      def self.column_names = []
    end)
  end
end
