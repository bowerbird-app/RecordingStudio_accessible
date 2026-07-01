# frozen_string_literal: true

require "test_helper"

class AccessRecordingCreationGuardTest < Minitest::Test
  Actor = Struct.new(:id) do
    def self.base_class = self
  end
  Access = Struct.new(:actor, :actor_type, :actor_id)
  Association = Struct.new(:target)
  ParentRecording = Struct.new(:id)

  class Errors
    attr_reader :added

    def initialize
      @added = []
    end

    def add(attribute, message)
      @added << [attribute, message]
    end
  end

  class DuplicateScope
    attr_reader :wheres, :joins_sql

    def initialize(exists:)
      @exists = exists
      @wheres = []
      @joins_sql = []
    end

    def where(*args)
      @wheres << args
      self
    end

    def not(*args)
      @wheres << [:not, args]
      self
    end

    def joins(sql)
      @joins_sql << sql
      self
    end

    def exists?
      @exists
    end
  end

  class Recording
    class << self
      attr_accessor :scope

      def validate(*); end
      def unscoped = scope
      def table_name = "recording_studio_recordings"
    end

    include RecordingStudioAccessible::AccessRecordingCreationGuard

    attr_accessor :id, :parent_recording, :parent_recording_id, :recordable, :recordable_type, :errors

    def initialize(recordable_type: "RecordingStudio::Access", recordable: nil, parent_recording: ParentRecording.new(1))
      @id = 100
      @recordable_type = recordable_type
      @recordable = recordable
      @parent_recording = parent_recording
      @parent_recording_id = parent_recording&.id
      @errors = Errors.new
    end

    def association(_name)
      Association.new(recordable)
    end

    def has_attribute?(name) # rubocop:disable Naming/PredicatePrefix
      name.to_s == "trashed_at"
    end
  end

  def setup
    ensure_access_class!
  end

  def teardown
    RecordingStudio.send(:remove_const, :Access) if @created_access_class
  end

  def test_prevents_direct_access_recording_creation_without_access_context
    recording = Recording.new

    RecordingStudioAccessible::Compatibility.stub(:access_parent_allowed?, true) do
      recording.send(:prevent_unsupported_access_recording_creation)
    end

    assert_includes recording.errors.added,
                    [:base, "Create access grants through RecordingStudioAccessible.grant_access"]
  end

  def test_allows_access_recording_creation_inside_access_context
    recording = Recording.new

    RecordingStudioAccessible::Compatibility.stub(:access_parent_allowed?, true) do
      RecordingStudioAccessible::AccessCreationContext.allow do
        recording.send(:prevent_unsupported_access_recording_creation)
      end
    end

    assert_empty recording.errors.added
  end

  def test_rejects_access_recording_when_parent_disallows_access_children
    recording = Recording.new

    RecordingStudioAccessible::Compatibility.stub(:access_parent_allowed?, false) do
      recording.send(:prevent_unsupported_access_recording_creation)
    end

    assert_includes recording.errors.added,
                    [:parent_recording, "does not allow RecordingStudio::Access children"]
  end

  def test_duplicate_guard_ignores_non_access_recordings_and_missing_parents
    non_access = Recording.new(recordable_type: "Message")
    missing_parent = Recording.new(parent_recording: nil)

    non_access.send(:prevent_duplicate_active_access_recording)
    missing_parent.send(:prevent_duplicate_active_access_recording)

    assert_empty non_access.errors.added
    assert_empty missing_parent.errors.added
  end

  def test_duplicate_guard_ignores_access_without_actor
    recording = Recording.new(recordable: Access.new(nil, nil, nil))

    recording.send(:prevent_duplicate_active_access_recording)

    assert_empty recording.errors.added
  end

  def test_duplicate_guard_adds_error_for_existing_active_actor_grant
    actor = Actor.new(42)
    recording = Recording.new(recordable: Access.new(actor, nil, nil))
    Recording.scope = DuplicateScope.new(exists: true)

    recording.send(:prevent_duplicate_active_access_recording)

    assert_includes recording.errors.added,
                    [:base, RecordingStudioAccessible::AccessRecordingCreationGuard::DUPLICATE_ACCESS_RECORDING_ERROR]
    assert_includes Recording.scope.wheres, [{ trashed_at: nil }]
    assert_includes Recording.scope.wheres,
                    [{ recording_studio_accesses: { actor_type: "AccessRecordingCreationGuardTest::Actor", actor_id: 42 } }]
  end

  def test_duplicate_guard_uses_stored_actor_type_and_id_when_present
    recording = Recording.new(recordable: Access.new(Actor.new(42), "Workspace", 7))
    Recording.scope = DuplicateScope.new(exists: false)

    recording.send(:prevent_duplicate_active_access_recording)

    assert_empty recording.errors.added
    assert_includes Recording.scope.wheres,
                    [{ recording_studio_accesses: { actor_type: "Workspace", actor_id: 7 } }]
  end

  private

  def ensure_access_class!
    return if RecordingStudio.const_defined?(:Access, false)

    @created_access_class = true
    RecordingStudio.const_set(:Access, Class.new)
  end
end
