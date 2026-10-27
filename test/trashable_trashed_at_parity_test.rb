# frozen_string_literal: true

require "test_helper"

# Proves Accessible uses Trashable query helpers (kept_sql / kept?) with the same
# additive semantics as main's where(trashed_at: nil) / trashed_at.nil?, and does
# not call recording_studio_trashable_active (which unscopes :trashed_at).
class TrashableTrashedAtParityTest < Minitest::Test
  KEPT_SQL = '"recording_studio_recordings"."trashed_at" IS NULL'

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

  def test_query_entry_point_is_loaded_without_engine
    assert defined?(RecordingStudioTrashable)
    assert_equal "0.12.0", RecordingStudioTrashable::VERSION
    refute defined?(RecordingStudioTrashable::Engine)
  end

  def test_direct_access_query_uses_kept_sql_not_trashable_active
    with_unscoped_column_and_kept_sql(true) do
      RecordingStudioAccessible::DirectAccessQuery.send(:active_recordings_scope)
    end

    assert_equal 0, @relation.trashable_active_calls
    assert_includes @relation.wheres, [KEPT_SQL]
  end

  def test_direct_access_query_skips_kept_filter_when_column_missing
    with_unscoped_column_and_kept_sql(false) do
      assert_same @relation, RecordingStudioAccessible::DirectAccessQuery.send(:active_recordings_scope)
    end

    assert_equal 0, @relation.trashable_active_calls
    assert_empty @relation.wheres
  end

  def test_audience_query_uses_kept_sql_not_trashable_active
    with_unscoped_column_and_kept_sql(true) do
      RecordingStudioAccessible::AudienceQuery.send(:live_recordings)
    end

    assert_equal 0, @relation.trashable_active_calls
    assert_includes @relation.wheres, [KEPT_SQL]
  end

  def test_authorization_class_methods_use_kept_sql_not_trashable_active
    host = Object.new
    host.extend(RecordingStudioAccessible::AuthorizationClassMethods)

    with_unscoped_column_and_kept_sql(true) do
      host.send(:active_recordings_scope)
    end

    assert_equal 0, @relation.trashable_active_calls
    assert_includes @relation.wheres, [KEPT_SQL]
  end

  def test_access_grant_integrity_uses_kept_sql_not_trashable_active
    service = RecordingStudioAccessible::Services::AccessGrantIntegrity.new

    with_unscoped_column_and_kept_sql(true) do
      service.send(:active_access_recordings)
    end

    assert_equal 0, @relation.trashable_active_calls
    assert_includes @relation.wheres, [KEPT_SQL]
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

  # Duck-typed objects may expose trashed_at without Trashable helpers (same as main).
  def test_lifecycle_active_recording_falls_back_to_trashed_at_nil_without_helper
    harness = LifecycleHarness.new
    duck = Struct.new(:trashed_at).new(nil)
    trashed_duck = Struct.new(:trashed_at).new(Time.utc(2026, 10, 13))

    refute_respond_to duck, :recording_studio_trashable_kept?
    assert harness.send(:active_recording?, duck)
    refute harness.send(:active_recording?, trashed_duck)
  end

  def test_dependent_access_active_recording_delegates_to_trashable_kept
    assert RecordingStudioAccessible::DependentAccess.send(:active_recording?,
                                                           RecordingStub.new(trashed_at: nil))
    refute RecordingStudioAccessible::DependentAccess.send(:active_recording?,
                                                           RecordingStub.new(trashed_at: Time.now))
    refute RecordingStudioAccessible::DependentAccess.send(:active_recording?, nil)
  end

  def test_dependent_access_active_recording_falls_back_to_trashed_at_nil_without_helper
    duck = Struct.new(:trashed_at).new(nil)
    trashed_duck = Struct.new(:trashed_at).new(Time.utc(2026, 10, 13))

    refute_respond_to duck, :recording_studio_trashable_kept?
    assert RecordingStudioAccessible::DependentAccess.send(:active_recording?, duck)
    refute RecordingStudioAccessible::DependentAccess.send(:active_recording?, trashed_duck)
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

  def test_lib_requires_query_entry_point_not_full_gem
    source = File.read(File.expand_path("../lib/recording_studio_accessible.rb", __dir__))

    assert_includes source, 'require "recording_studio_trashable/query"'
    refute_match(/require ["']recording_studio_trashable["']/, source)
  end

  def test_scope_helpers_source_uses_kept_sql_not_active_call
    paths = [
      "lib/recording_studio_accessible/direct_access_query.rb",
      "lib/recording_studio_accessible/audience_query.rb",
      "lib/recording_studio_accessible/authorization_class_methods.rb",
      "lib/recording_studio_accessible/services/access_grant_integrity.rb",
      "lib/recording_studio_accessible/access_recording_creation_guard.rb"
    ]

    paths.each do |relative|
      source = File.read(File.expand_path("../#{relative}", __dir__))
      assert_includes source, "recording_studio_trashable_kept_sql", relative
      refute_includes source, ".recording_studio_trashable_active", relative
    end
  end

  private

  def with_unscoped_column_and_kept_sql(column_present, &block)
    columns = column_present ? ["trashed_at"] : []
    RecordingStudio::Recording.stub(:unscoped, @relation) do
      RecordingStudio::Recording.stub(:column_names, columns) do
        RecordingStudio::Recording.stub(:recording_studio_trashable_kept_sql, KEPT_SQL, &block)
      end
    end
  end

  def ensure_recording_class!
    return if RecordingStudio.const_defined?(:Recording, false)

    @created_recording_class = true
    RecordingStudio.const_set(:Recording, Class.new do
      def self.unscoped = nil
      def self.column_names = []
      def self.recording_studio_trashable_kept_sql(*) = '"recording_studio_recordings"."trashed_at" IS NULL'
    end)
  end
end
