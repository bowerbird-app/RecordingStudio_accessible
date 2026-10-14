# frozen_string_literal: true

require "test_helper"

# Proves Accessible English is registered with RecordingStudio::Translation and
# that RecordingStudio.t / Copy.t fall back to this gem's en.yml when keys are
# deleted from the loaded backend.
class TranslationTest < Minitest::Test
  GEM_EN_YML = File.expand_path("../config/locales/en.yml", __dir__)
  SAMPLE_KEYS = {
    "recording_studio.accessible.manage.title" => "Manage access",
    "recording_studio.accessible.manage.add" => "Add access",
    "recording_studio.accessible.flashes.access_granted" => "Access granted.",
    "recording_studio.accessible.layout.title" => "Recording Studio Accessible",
    "recording_studio.accessible.errors.unknown_actor" => "Unknown actor",
    "recording_studio.accessible.home.index.anonymous" => "Anonymous"
  }.freeze

  def setup
    @previous_locales = I18n.available_locales
    I18n.available_locales = (@previous_locales + %i[en fr de]).uniq
    reset_english_backend!
    clear_locale_translations!(:fr)
    clear_locale_translations!(:de)
  end

  def teardown
    I18n.locale = I18n.default_locale
    I18n.available_locales = @previous_locales if @previous_locales
    reset_english_backend!
    clear_locale_translations!(:fr)
    clear_locale_translations!(:de)
  end

  def test_accessible_en_yml_path_is_registered_with_recording_studio_translation
    expected = File.expand_path(GEM_EN_YML)
    paths = RecordingStudio::Translation.send(:registered_shipped_english_paths)

    assert_includes paths, expected
    assert_equal "Manage access",
                 RecordingStudio::Translation.shipped_english.fetch(
                   "recording_studio.accessible.manage.title"
                 )
  end

  def test_deleted_loaded_english_falls_back_to_registered_gem_en_yml_text
    SAMPLE_KEYS.each_key do |key|
      delete_loaded_translation!(:en, key)
      delete_loaded_translation!(:fr, key)
    end

    SAMPLE_KEYS.each do |key, english|
      refute I18n.exists?(key, :en), "#{key} must be absent from loaded :en"
      refute I18n.exists?(key, :fr), "#{key} must be absent from loaded :fr"

      %i[en fr].each do |locale|
        I18n.with_locale(locale) do
          assert_equal english, RecordingStudio.t(key),
                       "#{key} should fall back via RecordingStudio.t in #{locale}"
          refute_match(/translation missing/i, RecordingStudio.t(key))

          relative = key.delete_prefix("#{RecordingStudioAccessible::Copy::PREFIX}.")
          assert_equal english, RecordingStudioAccessible::Copy.t(relative)
        end
      end
    end
  ensure
    I18n.backend.store_translations(:en, gem_english_tree)
  end

  def test_deleted_key_fallback_works_with_raise_on_missing_on_and_off
    key = "recording_studio.accessible.manage.title"
    delete_loaded_translation!(:en, key)
    delete_loaded_translation!(:fr, key)
    refute I18n.exists?(key, :en)
    refute I18n.exists?(key, :fr)

    [false, true].each do |raise_on_missing|
      %i[en fr].each do |locale|
        I18n.with_locale(locale) do
          if raise_on_missing
            assert_raises(I18n::MissingTranslationData) do
              I18n.t(key, locale: locale, raise: true)
            end
          end

          assert_equal "Manage access", RecordingStudio.t(key, raise: raise_on_missing)
          refute_match(/translation missing/i, RecordingStudio.t(key, raise: raise_on_missing))
        end
      end
    end
  ensure
    I18n.backend.store_translations(:en, gem_english_tree)
  end

  def test_missing_locale_falls_back_to_loaded_english_through_recording_studio_t
    I18n.with_locale(:de) do
      SAMPLE_KEYS.each do |key, english|
        refute I18n.exists?(key, :de), "#{key} must be absent in :de for this test"
        assert_equal english, RecordingStudio.t(key)
        refute_match(/translation missing/i, RecordingStudio.t(key))
      end
    end
  end

  private

  def gem_english_tree
    YAML.safe_load_file(GEM_EN_YML, aliases: true).fetch("en")
  end

  def reset_english_backend!
    I18n.backend.store_translations(:en, gem_english_tree)
  end

  def clear_locale_translations!(locale)
    I18n.backend.send(:init_translations) unless I18n.backend.initialized?
    translations = I18n.backend.send(:translations)
    locale_key = locale.to_sym
    node = translations[locale_key]
    return unless node.is_a?(Hash)

    translations[locale_key] = node.dup if node.frozen?
    translations[locale_key].delete(:recording_studio) if translations[locale_key].is_a?(Hash)
  end

  def delete_loaded_translation!(locale, full_key)
    I18n.exists?(full_key, locale)
    parts = full_key.split(".").map(&:to_sym)
    leaf = parts.pop
    translations = I18n.backend.send(:translations)
    locale_key = locale.to_sym
    translations[locale_key] = translations[locale_key].dup if translations[locale_key].frozen?

    node = translations[locale_key]
    parts.each do |part|
      break unless node.is_a?(Hash) && node[part].is_a?(Hash)

      node[part] = node[part].dup if node[part].frozen?
      node = node[part]
    end
    node.delete(leaf) if node.is_a?(Hash)
  end
end
