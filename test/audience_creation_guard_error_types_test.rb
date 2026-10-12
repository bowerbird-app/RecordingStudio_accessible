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

  def test_english_details_match_main_string_type
    recordable = AudienceRecordable.new
    recordable.send(:prevent_unsupported_direct_audience_creation)

    reference = ActiveModel::Errors.new(recordable)
    reference.add(:base, AudienceRecordable::WRITE_ERROR)

    assert_equal reference.details[:base], recordable.errors.details[:base]
    assert_equal [{ error: AudienceRecordable::WRITE_ERROR }], recordable.errors.details[:base]
    assert_includes recordable.errors.full_messages, AudienceRecordable::WRITE_ERROR
  end

  def test_french_full_messages_and_details_use_translated_string
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

    assert_equal [{ error: french }], recordable.errors.details[:base]
    assert_includes recordable.errors.full_messages, french
  ensure
    I18n.locale = previous_locale
    I18n.available_locales = previous_available if previous_available
    I18n.backend.instance_variable_set(:@translations, previous_translations) if previous_translations
  end

  def test_host_english_override_renders
    host = "HOST Create via set_audience!"
    previous_translations = deep_plain_copy(I18n.backend.translations)

    I18n.backend.store_translations(
      :en,
      recording_studio: {
        accessible: { recordables: { access_rule: { write_error: host } } }
      }
    )

    recordable = AudienceRecordable.new
    recordable.send(:prevent_unsupported_direct_audience_creation)

    assert_equal [{ error: host }], recordable.errors.details[:base]
    assert_includes recordable.errors.full_messages, host
  ensure
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
