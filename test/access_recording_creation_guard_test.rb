# frozen_string_literal: true

require "test_helper"

class AccessRecordingCreationGuardTest < Minitest::Test
  Actor = Struct.new(:id) do
    def self.base_class = self
  end
  Access = Struct.new(:actor, :actor_type, :actor_id)
  Association = Struct.new(:target)
  ParentRecording = Struct.new(:id, :recordable_type, keyword_init: true)

  class Errors
    attr_reader :added, :details, :messages

    def initialize
      @added = []
      @details = Hash.new { |hash, key| hash[key] = [] }
      @messages = Hash.new { |hash, key| hash[key] = [] }
    end

    # Mirrors ActiveModel::Errors#add so type stays distinct from message:.
    def add(attribute, type = :invalid, **options)
      @added << [attribute, type]
      @details[attribute] << { error: type }
      @messages[attribute] << (options[:message] || type)
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

    def initialize(recordable_type: "RecordingStudio::Access", recordable: nil, parent_recording: ParentRecording.new(id: 1, recordable_type: "Workspace"))
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
    create_via_grant = "Create access grants through RecordingStudioAccessible.grant_access"

    RecordingStudioAccessible::SharedRootAccess.stub(:target?, false) do
      RecordingStudioAccessible::Compatibility.stub(:access_parent_allowed?, true) do
        recording.send(:prevent_unsupported_access_recording_creation)
      end
    end

    assert_includes recording.errors.added, [:base, create_via_grant]
    assert_equal [{ error: create_via_grant }], recording.errors.details[:base]
    assert_equal [create_via_grant], recording.errors.messages[:base]
  end

  def test_allows_access_recording_creation_inside_access_context
    recording = Recording.new

    RecordingStudioAccessible::SharedRootAccess.stub(:target?, false) do
      RecordingStudioAccessible::Compatibility.stub(:access_parent_allowed?, true) do
        RecordingStudioAccessible::AccessCreationContext.allow do
          recording.send(:prevent_unsupported_access_recording_creation)
        end
      end
    end

    assert_empty recording.errors.added
  end

  def test_rejects_access_recording_when_parent_is_shared_root
    recording = Recording.new(parent_recording: ParentRecording.new(id: 1, recordable_type: "MessageRoot"))
    denied = RecordingStudioAccessible::SharedRootAccess::GRANT_DENIED_MESSAGE

    RecordingStudioAccessible::SharedRootAccess.stub(:target?, true) do
      recording.send(:prevent_unsupported_access_recording_creation)
    end

    assert_includes recording.errors.added, [:parent_recording, denied]
    assert_equal [{ error: denied }], recording.errors.details[:parent_recording]
  end

  def test_rejects_access_recording_when_parent_disallows_access_children
    recording = Recording.new
    not_allowed = "does not allow RecordingStudio::Access children"

    RecordingStudioAccessible::SharedRootAccess.stub(:target?, false) do
      RecordingStudioAccessible::Compatibility.stub(:access_parent_allowed?, false) do
        recording.send(:prevent_unsupported_access_recording_creation)
      end
    end

    assert_includes recording.errors.added, [:parent_recording, not_allowed]
    assert_equal [{ error: not_allowed }], recording.errors.details[:parent_recording]
  end

  def test_translated_guard_message_keeps_english_error_type_in_details
    recording = Recording.new
    create_via_grant = "Create access grants through RecordingStudioAccessible.grant_access"
    french = "Créer via grant_access"
    previous_locale = I18n.locale
    previous_available = I18n.available_locales.dup
    previous_translations = deep_plain_copy(I18n.backend.translations)

    I18n.available_locales = previous_available | %i[fr]
    I18n.backend.store_translations(
      :fr,
      recording_studio: { accessible: { errors: { create_via_grant_access: french } } }
    )
    I18n.locale = :fr

    RecordingStudioAccessible::SharedRootAccess.stub(:target?, false) do
      RecordingStudioAccessible::Compatibility.stub(:access_parent_allowed?, true) do
        recording.send(:prevent_unsupported_access_recording_creation)
      end
    end

    assert_includes recording.errors.added, [:base, create_via_grant]
    assert_equal [{ error: create_via_grant }], recording.errors.details[:base]
    assert_equal [french], recording.errors.messages[:base]
  ensure
    I18n.locale = previous_locale
    I18n.available_locales = previous_available if previous_available
    I18n.backend.instance_variable_set(:@translations, previous_translations) if previous_translations
  end

  def deep_plain_copy(value)
    case value
    when Hash
      value.each_with_object({}) { |(key, nested), copy| copy[key] = deep_plain_copy(nested) }
    when Array
      value.map { |nested| deep_plain_copy(nested) }
    else
      value
    end
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

    duplicate = RecordingStudioAccessible::AccessRecordingCreationGuard::DUPLICATE_ACCESS_RECORDING_ERROR
    assert_includes recording.errors.added, [:base, duplicate]
    assert_equal [{ error: duplicate }], recording.errors.details[:base]
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
