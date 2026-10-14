# frozen_string_literal: true

require_relative "../test_helper"

# Behavioral renders: a locale without translations shows loaded / shipped
# English for Accessible manage-access copy. Uses :de so boot-loaded host
# English overrides and dummy :fr do not interfere with the missing-locale case.
class EnglishFallbackTest < ActionDispatch::IntegrationTest
  MANAGE_TITLE_KEY = "recording_studio.accessible.manage.title"

  setup do
    @admin = User.find_by(email: "admin@admin.com") ||
             User.create!(email: "admin@admin.com", password: "Password", password_confirmation: "Password")
    workspace = Workspace.create!(name: "English Fallback Workspace")
    @recording = create_root_recording(workspace)
    bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(recording: @recording, actor: @admin)
    assert bootstrap.success?, bootstrap.error
    @previous_locales = I18n.available_locales
    I18n.available_locales = (@previous_locales + %i[en de fr]).uniq
  end

  teardown do
    I18n.locale = I18n.default_locale
    I18n.available_locales = @previous_locales if @previous_locales
  end

  test "missing locale without translations renders gem english on manage access page" do
    I18n.with_locale(:de) do
      refute locale_has_own_translation?(:de, MANAGE_TITLE_KEY),
             ":de must not ship its own manage.title (fallbacks may still resolve via :en)"

      sign_in @admin
      get "/recording_studio_accessible/recordings/#{@recording.id}/accesses"

      assert_response :success
      assert_includes @response.body, "Manage access"
      refute_match(/translation missing/i, @response.body)
      refute_includes @response.body, "Translation missing"
    end
  end

  test "english render matches gem english strings from main" do
    I18n.with_locale(:en) do
      sign_in @admin
      get "/recording_studio_accessible/recordings/#{@recording.id}/accesses"

      assert_response :success
      assert_includes @response.body, "Manage access"
      assert_includes @response.body, "Add access"
      assert_includes @response.body, "People with access"
      refute_match(/translation missing/i, @response.body)
    end
  end

  test "methods page follows locale so a literal english title fails under french" do
    french_title = I18n.t("recording_studio.accessible.home.methods.grant_title", locale: :fr)
    english_title = "Grant access with RecordingStudioAccessible.grant_access"
    refute_equal english_title, french_title

    sign_in @admin
    patch "/recording_studio_internationalization/locale",
          params: { locale: "fr", return_to: "/recording_studio_accessible/methods" }
    follow_redirect!

    assert_response :success
    assert_includes @response.body, french_title
    # Section titles use Copy.t; code samples stay English on purpose.
    assert_includes @response.body, "<h2"
    assert_match(%r{<h2[^>]*>\s*#{Regexp.escape(french_title)}\s*</h2>}m, @response.body)
  end

  test "deleted english key on manage access shows shipped Manage access without translation missing" do
    delete_loaded_translation!(:en, MANAGE_TITLE_KEY)
    delete_loaded_translation!(:fr, MANAGE_TITLE_KEY)

    refute I18n.exists?(MANAGE_TITLE_KEY, :en)
    refute I18n.exists?(MANAGE_TITLE_KEY, :fr)

    previous_raise = ActionView::Helpers::TranslationHelper.raise_on_missing_translations

    [false, true].each do |raise_on_missing|
      ActionView::Helpers::TranslationHelper.raise_on_missing_translations = raise_on_missing

      %i[en fr].each do |locale|
        I18n.with_locale(locale) do
          sign_in @admin
          get "/recording_studio_accessible/recordings/#{@recording.id}/accesses"

          assert_response :success
          assert_includes @response.body, "Manage access"
          refute_match(/translation missing/i, @response.body)
        end
      end
    end
  ensure
    ActionView::Helpers::TranslationHelper.raise_on_missing_translations = previous_raise
    I18n.reload!
  end

  test "shipped english table becomes a new object after rails reloader reload" do
    before = RecordingStudioAccessible::Translation.shipped_english
    refute_empty before

    previous_cache_classes = Rails.application.config.cache_classes
    # Test env normally keeps cache_classes on; metrics then treats a second
    # register during reload as a duplicate. Flip it off for this reload only.
    Rails.application.config.cache_classes = false
    RecordingStudioMetrics.registry.reset! if defined?(RecordingStudioMetrics)

    Rails.application.reloader.reload!

    after = RecordingStudioAccessible::Translation.shipped_english
    refute_same before, after
    assert_equal before, after
  ensure
    Rails.application.config.cache_classes = previous_cache_classes if previous_cache_classes != nil
  end

  test "global I18n config keeps fallbacks load_path available_locales and exception handler" do
    snapshot = i18n_config_snapshot
    gem_en = File.expand_path(RecordingStudioAccessible::Engine.root.join("config/locales/en.yml"))
    boot_en = Rails.root.join("config/locales/accessible_boot_override.en.yml").to_s

    assert_includes snapshot.fetch(:load_path), File.expand_path(gem_en)
    assert_includes snapshot.fetch(:load_path), File.expand_path(boot_en)
    assert_operator snapshot.fetch(:load_path).index(File.expand_path(gem_en)),
                    :<,
                    snapshot.fetch(:load_path).index(File.expand_path(boot_en))
    assert snapshot.fetch(:exception_handler), "expected an I18n exception handler"
    assert_includes snapshot.fetch(:available_locales), :en
  end

  private

  def i18n_config_snapshot
    {
      load_path: I18n.load_path.map { |path| File.expand_path(path) },
      available_locales: Array(I18n.available_locales).map(&:to_sym).sort,
      exception_handler: I18n.exception_handler,
      enforce_available_locales: I18n.enforce_available_locales,
      fallbacks_class: (I18n.fallbacks.class.name if I18n.respond_to?(:fallbacks))
    }
  end

  def locale_has_own_translation?(locale, full_key)
    I18n.backend.send(:init_translations) unless I18n.backend.initialized?
    node = I18n.backend.send(:translations)[locale.to_sym]
    return false unless node.is_a?(Hash)

    full_key.split(".").map(&:to_sym).each do |part|
      return false unless node.is_a?(Hash) && node.key?(part)

      node = node[part]
    end
    !node.nil?
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
