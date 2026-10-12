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
    previous_load_path = I18n.load_path.dup
    I18n.load_path << HOST_OVERRIDE_LOCALE
    I18n.reload!

    sign_in @admin
    get "/recording_studio_accessible/recordings/#{@recording.id}/accesses"

    assert_response :success
    assert_includes response.body, "HOST Manage access wins"
    refute_includes response.body, "Manage access</"
    assert_equal "HOST Manage access wins",
                 I18n.t("recording_studio.accessible.manage.title")
  ensure
    I18n.load_path.replace(previous_load_path)
    I18n.reload!
  end

  test "default english returns after host override is removed" do
    assert_equal "Manage access", I18n.t("recording_studio.accessible.manage.title")

    sign_in @admin
    get "/recording_studio_accessible/recordings/#{@recording.id}/accesses"

    assert_response :success
    assert_includes response.body, "Manage access"
    refute_includes response.body, "HOST Manage access wins"
  end
end
