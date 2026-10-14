# frozen_string_literal: true

require_relative "../test_helper"

# Boot-loaded host English override for a rarely shown manage.expired label
# wins on a real manage-access page. Fixture:
# test/dummy/config/locales/accessible_boot_override.en.yml
class EnglishFallbackBootOverrideTest < ActionDispatch::IntegrationTest
  HOST_OVERRIDE_LOCALE = Rails.root.join("config/locales/accessible_boot_override.en.yml").to_s.freeze
  KEY = "recording_studio.accessible.manage.expired"
  HOST = "HOST Expired boot"
  GEM_ENGLISH = "Expired"

  setup do
    @admin = User.find_by(email: "admin@admin.com") ||
             User.create!(email: "admin@admin.com", password: "Password", password_confirmation: "Password")
    workspace = Workspace.create!(name: "Boot Override Workspace")
    @recording = create_root_recording(workspace)
    bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(recording: @recording, actor: @admin)
    assert bootstrap.success?, bootstrap.error

    # Force I18n to initialize before store_translations / assertions.
    I18n.t("recording_studio.accessible.manage.title")
  end

  test "boot-loaded host english override wins on manage access expired label" do
    assert_boot_loaded_override_preconditions!

    invite = RecordingStudioAccessible.invite_access(
      recording: @recording,
      email: "expired-invite@example.com",
      role: "view",
      manager_actor: @admin
    )
    assert invite.success?, invite.error
    invitation = RecordingStudioAccessible::AccessInvitation.unclosed.find_by!(email: "expired-invite@example.com")
    invitation.update!(expires_at: 1.minute.ago)
    assert invitation.expired?

    sign_in @admin
    get "/recording_studio_accessible/recordings/#{@recording.id}/accesses"

    assert_response :success
    assert_includes @response.body, HOST
    refute_match(/(?<!HOST )Expired/, @response.body)
    refute_includes @response.body, ">#{GEM_ENGLISH}<"
    assert_equal HOST, I18n.t(KEY)
    assert_equal HOST, RecordingStudio.t(KEY)
    assert_equal HOST, RecordingStudioAccessible::Copy.t("manage.expired")
  end

  private

  def assert_boot_loaded_override_preconditions!
    assert File.exist?(HOST_OVERRIDE_LOCALE), "expected boot-loaded host override at #{HOST_OVERRIDE_LOCALE}"
    assert_includes File.expand_path(HOST_OVERRIDE_LOCALE), "/config/locales/"

    load_path = I18n.load_path.map { |path| File.expand_path(path) }
    gem_en = File.expand_path(RecordingStudioAccessible::Engine.root.join("config/locales/en.yml"))
    host_en = File.expand_path(HOST_OVERRIDE_LOCALE)

    assert_includes load_path, gem_en
    assert_includes load_path, host_en
    assert_operator load_path.index(gem_en), :<, load_path.index(host_en),
                    "gem en.yml must load before host boot override"

    original_load_path = I18n.load_path.dup
    assert_equal HOST, I18n.t(KEY), "I18n.t must return HOST before the page render"
    assert_equal original_load_path, I18n.load_path, "load_path must stay untouched"
    refute_equal GEM_ENGLISH, I18n.t(KEY)
  end
end
