# frozen_string_literal: true

require "test_helper"

# Proves Accessible filters through Recording.kept and does not call removed
# Trashable scopes. In-memory checks use recording_studio_trashable_kept? when
# the object has it. A bare trashed_at attribute is not a filter.
class TrashableTrashedAtParityTest < Minitest::Test
  class RelationSpy
    attr_reader :wheres, :kept_calls

    def initialize
      @wheres = []
      @kept_calls = 0
    end

    def kept
      @kept_calls += 1
      self
    end

    def where(*args)
      @wheres << args
      self
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
    @relation = RelationSpy.new
  end

  def test_query_entry_point_is_loaded_without_engine
    assert defined?(RecordingStudioTrashable)
    assert_equal "0.16.0", RecordingStudioTrashable::VERSION
    refute defined?(RecordingStudioTrashable::Engine)
  end

  def test_direct_access_query_uses_kept
    with_unscoped do
      assert_same @relation, RecordingStudioAccessible::DirectAccessQuery.send(:active_recordings_scope)
    end

    assert_equal 1, @relation.kept_calls
    assert_empty @relation.wheres
  end

  def test_audience_query_uses_kept
    with_unscoped do
      assert_same @relation, RecordingStudioAccessible::AudienceQuery.send(:live_recordings)
    end

    assert_equal 1, @relation.kept_calls
  end

  def test_authorization_class_methods_use_kept
    host = Object.new
    host.extend(RecordingStudioAccessible::AuthorizationClassMethods)

    with_unscoped do
      assert_same @relation, host.send(:active_recordings_scope)
    end

    assert_equal 1, @relation.kept_calls
  end

  def test_access_grant_integrity_uses_kept
    service = RecordingStudioAccessible::Services::AccessGrantIntegrity.new

    with_unscoped do
      service.send(:active_access_recordings)
    end

    assert_equal 1, @relation.kept_calls
    assert_includes @relation.wheres, [{ recordable_type: "RecordingStudio::Access" }]
  end

  def test_lifecycle_active_recording_delegates_to_trashable_kept
    harness = LifecycleHarness.new

    assert harness.send(:active_recording?, RecordingStub.new(trashed_at: nil))
    refute harness.send(:active_recording?, RecordingStub.new(trashed_at: Time.now))
  end

  def test_lifecycle_active_recording_passes_without_trashed_at
    harness = LifecycleHarness.new

    assert harness.send(:active_recording?, Object.new)
  end

  def test_lifecycle_active_recording_ignores_trashed_at_without_kept_helper
    harness = LifecycleHarness.new
    duck = Struct.new(:trashed_at).new(nil)
    trashed_duck = Struct.new(:trashed_at).new(Time.utc(2026, 10, 13))

    refute_respond_to duck, :recording_studio_trashable_kept?
    assert harness.send(:active_recording?, duck)
    assert harness.send(:active_recording?, trashed_duck)
  end

  def test_dependent_access_active_recording_delegates_to_trashable_kept
    assert RecordingStudioAccessible::DependentAccess.send(:active_recording?,
                                                           RecordingStub.new(trashed_at: nil))
    refute RecordingStudioAccessible::DependentAccess.send(:active_recording?,
                                                           RecordingStub.new(trashed_at: Time.now))
    refute RecordingStudioAccessible::DependentAccess.send(:active_recording?, nil)
  end

  def test_dependent_access_ignores_trashed_at_without_kept_helper
    duck = Struct.new(:trashed_at).new(nil)
    trashed_duck = Struct.new(:trashed_at).new(Time.utc(2026, 10, 13))

    refute_respond_to duck, :recording_studio_trashable_kept?
    assert RecordingStudioAccessible::DependentAccess.send(:active_recording?, duck)
    assert RecordingStudioAccessible::DependentAccess.send(:active_recording?, trashed_duck)
  end

  def test_kept_predicate_matches_nil_check_for_datetime_values
    kept = RecordingStub.new(trashed_at: nil)
    trashed = RecordingStub.new(trashed_at: Time.utc(2026, 10, 13))

    assert_equal kept.trashed_at.nil?, kept.recording_studio_trashable_kept?
    assert_equal trashed.trashed_at.nil?, trashed.recording_studio_trashable_kept?
  end

  def test_accessible_does_not_soft_void_on_destroy_path
    source = File.read(
      RecordingStudioAccessible::Engine.root.join("lib/recording_studio_accessible/services/access_record_lifecycle.rb")
    )

    assert_includes source, "access_recording.destroy!"
    refute_includes source, "void_recording!"
    refute_includes source, "recording_studio_trashable_void!"
  end

  def test_lib_requires_query_entry_point_not_full_gem
    source = File.read(RecordingStudioAccessible::Engine.root.join("lib/recording_studio_accessible.rb"))

    assert_includes source, 'require "recording_studio_trashable/query"'
    refute_match(/require ["']recording_studio_trashable["']/, source)
  end

  def test_sources_use_core_kept_and_not_removed_trashable_helpers
    root = RecordingStudioAccessible::Engine.root
    paths = Dir[root.join("{lib,app}/**/*.rb")]
    combined = paths.map { |path| File.read(path) }.join("\n")

    assert_includes combined, ".kept"
    assert_includes combined, "RecordingStudio.kept_sql"
    refute_includes combined, "recording_studio_trashable_kept_sql"
    refute_includes combined, "recording_studio_trashable_active"
    refute_includes combined, "recording_studio_trashable_including_trashed"
    refute_includes combined, "recording_studio_trashable_trashed_sql"
    refute_includes combined, 'column_names.include?("trashed_at")'
    refute_includes combined, "has_attribute?(:trashed_at)"
    refute_includes combined, "trashed_at.nil?"
  end

  private

  def with_unscoped(&block)
    RecordingStudio::Recording.stub(:unscoped, @relation, &block)
  end
end
