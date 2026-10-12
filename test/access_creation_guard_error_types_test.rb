# frozen_string_literal: true

require "test_helper"
require "active_model"

class AccessCreationGuardErrorTypesTest < Minitest::Test
  CREATE_VIA_GRANT = "Create access grants through RecordingStudioAccessible.grant_access"

  class AccessRecordable
    extend ActiveModel::Naming
    include ActiveModel::Conversion

    class << self
      def validate(*); end
    end

    include RecordingStudioAccessible::AccessCreationGuard

    attr_reader :errors

    def initialize
      @errors = ActiveModel::Errors.new(self)
    end

    def persisted? = false
  end

  def test_create_via_grant_error_type_matches_main_english_string
    recordable = AccessRecordable.new
    recordable.send(:prevent_unsupported_direct_creation)

    reference = ActiveModel::Errors.new(recordable)
    reference.add(:base, CREATE_VIA_GRANT)

    assert_equal reference.details[:base], recordable.errors.details[:base]
    assert_equal [{ error: CREATE_VIA_GRANT }], recordable.errors.details[:base]
    assert recordable.errors.added?(:base, CREATE_VIA_GRANT)
  end

  def test_create_via_grant_error_type_stays_english_under_french_locale
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

    recordable = AccessRecordable.new
    recordable.send(:prevent_unsupported_direct_creation)

    reference = ActiveModel::Errors.new(recordable)
    reference.add(:base, CREATE_VIA_GRANT)

    assert_equal reference.details[:base], recordable.errors.details[:base]
    assert_equal [{ error: CREATE_VIA_GRANT }], recordable.errors.details[:base]
    assert recordable.errors.added?(:base, CREATE_VIA_GRANT)
    # String error types are the displayed message in ActiveModel; details stay English.
    assert_equal [CREATE_VIA_GRANT], recordable.errors[:base]
  ensure
    I18n.locale = previous_locale
    I18n.available_locales = previous_available if previous_available
    I18n.backend.instance_variable_set(:@translations, previous_translations) if previous_translations
  end

  private

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
end
