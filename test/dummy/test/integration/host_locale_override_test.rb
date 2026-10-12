# frozen_string_literal: true

require_relative "../test_helper"

class HostLocaleOverrideTest < ActionDispatch::IntegrationTest
  HOST_OVERRIDE_LOCALE = File.expand_path("../locales/accessible_host_override.en.yml", __dir__).freeze

  setup do
    @admin = User.find_by(email: "admin@admin.com") ||
             User.create!(email: "admin@admin.com", password: "Password", password_confirmation: "Password")
    workspace = Workspace.create!(name: "Host Override Workspace")
    @recording = create_root_recording(workspace)
    bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(recording: @recording, actor: @admin)
    assert bootstrap.success?, bootstrap.error
  end

  test "host locale file override wins over gem english on manage access page" do
    with_restored_i18n_backend do
      I18n.load_path << HOST_OVERRIDE_LOCALE
      I18n.backend.load_translations(HOST_OVERRIDE_LOCALE)

      sign_in @admin
      get "/recording_studio_accessible/recordings/#{@recording.id}/accesses"

      assert_response :success
      assert_includes response.body, "HOST Manage access wins"
      refute_includes response.body, "Manage access</"
      assert_equal "HOST Manage access wins",
                   I18n.t("recording_studio.accessible.manage.title")
    end
  end

  test "default english returns after host override is removed" do
    assert_equal "Manage access", I18n.t("recording_studio.accessible.manage.title")

    sign_in @admin
    get "/recording_studio_accessible/recordings/#{@recording.id}/accesses"

    assert_response :success
    assert_includes response.body, "Manage access"
    refute_includes response.body, "HOST Manage access wins"
  end

  private

  # Snapshot load path + Simple backend translations, then restore without a bare
  # I18n.reload! so any store_translations from other tests stay intact.
  def with_restored_i18n_backend
    previous_load_path = I18n.load_path.dup
    previous_translations = i18n_backend_translations_snapshot
    yield
  ensure
    I18n.load_path.replace(previous_load_path)
    restore_i18n_backend_translations(previous_translations) if previous_translations
  end

  def i18n_backend_translations_snapshot
    backend = I18n.backend
    backend.send(:init_translations) unless backend.initialized?
    translations =
      if backend.respond_to?(:translations)
        backend.translations
      else
        backend.instance_variable_get(:@translations)
      end
    return unless translations

    deep_plain_copy(translations)
  end

  def restore_i18n_backend_translations(snapshot)
    backend = I18n.backend
    backend.instance_variable_set(:@translations, snapshot)
    backend.instance_variable_set(:@initialized, true) if backend.instance_variable_defined?(:@initialized)
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
end
