# frozen_string_literal: true

require "test_helper"
require "active_model"

class AccessRecordingCreationGuardTest < Minitest::Test
  Actor = Struct.new(:id) do
    def self.base_class = self
  end
  Access = Struct.new(:actor, :actor_type, :actor_id)
  Association = Struct.new(:target)
  ParentRecording = Struct.new(:id, :recordable_type, keyword_init: true)

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
    extend ActiveModel::Naming
    include ActiveModel::Conversion

    class << self
      attr_accessor :scope

      def validate(*); end
      def unscoped = scope
      def table_name = "recording_studio_recordings"

      def recording_studio_trashable_kept_sql(_table = table_name)
        '"recording_studio_recordings"."trashed_at" IS NULL'
      end
    end

    include RecordingStudioAccessible::AccessRecordingCreationGuard

    attr_accessor :id, :parent_recording, :parent_recording_id, :recordable, :recordable_type
    attr_reader :errors

    def initialize(recordable_type: "RecordingStudio::Access", recordable: nil, parent_recording: ParentRecording.new(id: 1, recordable_type: "Workspace"))
      @id = 100
      @recordable_type = recordable_type
      @recordable = recordable
      @parent_recording = parent_recording
      @parent_recording_id = parent_recording&.id
      @errors = ActiveModel::Errors.new(self)
    end

    def persisted? = false

    def association(_name)
      Association.new(recordable)
    end

    def has_attribute?(name) # rubocop:disable Naming/PredicatePrefix
      name.to_s == "trashed_at"
    end
  end

  CREATE_VIA_GRANT = "Create access grants through RecordingStudioAccessible.grant_access"
  ACCESS_CHILDREN_NOT_ALLOWED = "does not allow RecordingStudio::Access children"

  def setup
    ensure_access_class!
  end

  def teardown
    RecordingStudio.send(:remove_const, :Access) if @created_access_class
  end

  def test_prevents_direct_access_recording_creation_without_access_context
    recording = Recording.new

    RecordingStudioAccessible::SharedRootAccess.stub(:target?, false) do
      RecordingStudioAccessible::Compatibility.stub(:access_parent_allowed?, true) do
        recording.send(:prevent_unsupported_access_recording_creation)
      end
    end

    assert_english_details_match_main(recording.errors, :base, CREATE_VIA_GRANT)
    assert_includes recording.errors.full_messages, CREATE_VIA_GRANT
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

    assert_empty recording.errors.details
  end

  def test_rejects_access_recording_when_parent_is_shared_root
    recording = Recording.new(parent_recording: ParentRecording.new(id: 1, recordable_type: "MessageRoot"))
    denied = RecordingStudioAccessible::SharedRootAccess::GRANT_DENIED_MESSAGE

    RecordingStudioAccessible::SharedRootAccess.stub(:target?, true) do
      recording.send(:prevent_unsupported_access_recording_creation)
    end

    assert_english_details_match_main(recording.errors, :parent_recording, denied)
  end

  def test_rejects_access_recording_when_parent_disallows_access_children
    recording = Recording.new

    RecordingStudioAccessible::SharedRootAccess.stub(:target?, false) do
      RecordingStudioAccessible::Compatibility.stub(:access_parent_allowed?, false) do
        recording.send(:prevent_unsupported_access_recording_creation)
      end
    end

    assert_english_details_match_main(recording.errors, :parent_recording, ACCESS_CHILDREN_NOT_ALLOWED)
  end

  def test_french_locale_full_messages_and_details_use_translated_string
    recording = Recording.new
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

    assert_equal [{ error: french }], recording.errors.details[:base]
    assert_includes recording.errors.full_messages, french
    refute_includes recording.errors.full_messages, CREATE_VIA_GRANT
  ensure
    I18n.locale = previous_locale
    I18n.available_locales = previous_available if previous_available
    I18n.backend.instance_variable_set(:@translations, previous_translations) if previous_translations
  end

  def test_host_english_override_renders_on_guard_error
    recording = Recording.new
    host = "HOST Create via grant_access"
    previous_translations = deep_plain_copy(I18n.backend.translations)

    I18n.backend.store_translations(
      :en,
      recording_studio: { accessible: { errors: { create_via_grant_access: host } } }
    )

    RecordingStudioAccessible::SharedRootAccess.stub(:target?, false) do
      RecordingStudioAccessible::Compatibility.stub(:access_parent_allowed?, true) do
        recording.send(:prevent_unsupported_access_recording_creation)
      end
    end

    assert_equal [{ error: host }], recording.errors.details[:base]
    assert_includes recording.errors.full_messages, host
  ensure
    I18n.backend.instance_variable_set(:@translations, previous_translations) if previous_translations
  end

  def test_duplicate_guard_ignores_non_access_recordings_and_missing_parents
    non_access = Recording.new(recordable_type: "Message")
    missing_parent = Recording.new(parent_recording: nil)

    non_access.send(:prevent_duplicate_active_access_recording)
    missing_parent.send(:prevent_duplicate_active_access_recording)

    assert_empty non_access.errors.details
    assert_empty missing_parent.errors.details
  end

  def test_duplicate_guard_ignores_access_without_actor
    recording = Recording.new(recordable: Access.new(nil, nil, nil))

    recording.send(:prevent_duplicate_active_access_recording)

    assert_empty recording.errors.details
  end

  def test_duplicate_guard_adds_error_for_existing_active_actor_grant
    actor = Actor.new(42)
    recording = Recording.new(recordable: Access.new(actor, nil, nil))
    Recording.scope = DuplicateScope.new(exists: true)

    recording.send(:prevent_duplicate_active_access_recording)

    duplicate = RecordingStudioAccessible::AccessRecordingCreationGuard::DUPLICATE_ACCESS_RECORDING_ERROR
    assert_english_details_match_main(recording.errors, :base, duplicate)
    assert_includes Recording.scope.wheres, ['"recording_studio_recordings"."trashed_at" IS NULL']
    assert_includes Recording.scope.wheres,
                    [{ recording_studio_accesses: { actor_type: "AccessRecordingCreationGuardTest::Actor", actor_id: 42 } }]
  end

  def test_duplicate_guard_uses_stored_actor_type_and_id_when_present
    recording = Recording.new(recordable: Access.new(Actor.new(42), "Workspace", 7))
    Recording.scope = DuplicateScope.new(exists: false)

    recording.send(:prevent_duplicate_active_access_recording)

    assert_empty recording.errors.details
    assert_includes Recording.scope.wheres,
                    [{ recording_studio_accesses: { actor_type: "Workspace", actor_id: 7 } }]
  end

  private

  # English default: must match main's errors.add(attr, "<English>") details byte-for-byte.
  def assert_english_details_match_main(actual_errors, attribute, main_english)
    reference = ActiveModel::Errors.new(actual_errors.instance_variable_get(:@base))
    reference.add(attribute, main_english)
    assert_equal reference.details[attribute], actual_errors.details[attribute]
    assert_equal [{ error: main_english }], actual_errors.details[attribute]
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

  def ensure_access_class!
    return if RecordingStudio.const_defined?(:Access, false)

    @created_access_class = true
    RecordingStudio.const_set(:Access, Class.new)
  end
end
