# frozen_string_literal: true

require "test_helper"
require "active_model"

class AudienceCreationGuardErrorTypesTest < Minitest::Test
  class AudienceRecordable
    extend ActiveModel::Naming
    include ActiveModel::Conversion

    WRITE_ERROR = "Create audiences through RecordingStudioAccessible.set_audience!"

    class << self
      def validate(*); end

      def audience_write_error
        RecordingStudioAccessible::Copy.t(
          "recordables.access_rule.write_error",
          default: WRITE_ERROR
        )
      end
    end

    include RecordingStudioAccessible::AudienceCreationGuard

    attr_reader :errors

    def initialize
      @errors = ActiveModel::Errors.new(self)
    end

    def persisted? = false
  end

  def test_audience_write_error_type_matches_main_english_string
    recordable = AudienceRecordable.new
    recordable.send(:prevent_unsupported_direct_audience_creation)

    reference = ActiveModel::Errors.new(recordable)
    reference.add(:base, AudienceRecordable::WRITE_ERROR)

    assert_equal reference.details[:base], recordable.errors.details[:base]
    assert_equal [{ error: AudienceRecordable::WRITE_ERROR }], recordable.errors.details[:base]
    assert recordable.errors.added?(:base, AudienceRecordable::WRITE_ERROR)
  end

  def test_audience_write_error_type_stays_english_under_french_locale
    french = "Créer via set_audience!"
    previous_locale = I18n.locale
    previous_available = I18n.available_locales.dup
    previous_translations = deep_plain_copy(I18n.backend.translations)

    I18n.available_locales = previous_available | %i[fr]
    I18n.backend.store_translations(
      :fr,
      recording_studio: {
        accessible: { recordables: { access_rule: { write_error: french } } }
      }
    )
    I18n.locale = :fr

    recordable = AudienceRecordable.new
    recordable.send(:prevent_unsupported_direct_audience_creation)

    reference = ActiveModel::Errors.new(recordable)
    reference.add(:base, AudienceRecordable::WRITE_ERROR)

    assert_equal reference.details[:base], recordable.errors.details[:base]
    assert_equal [{ error: AudienceRecordable::WRITE_ERROR }], recordable.errors.details[:base]
    assert recordable.errors.added?(:base, AudienceRecordable::WRITE_ERROR)
    # String error types are the displayed message in ActiveModel; details stay English.
    assert_equal [AudienceRecordable::WRITE_ERROR], recordable.errors[:base]
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
