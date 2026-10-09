# frozen_string_literal: true

require "test_helper"
require "yaml"

class LocalesTest < Minitest::Test
  Copy = RecordingStudioAccessible::Copy

  # I18n template tokens use %{name}; RuboCop prefers %<name>s for Kernel#sprintf.
  # rubocop:disable Style/FormatStringToken
  ACTOR_ACCESS_POINTS_KEYS = {
    "title" => "%{actor} access points",
    "workspace" => "Workspace: %{name}",
    "columns.access_point" => "Access point",
    "columns.role" => "Role",
    "columns.access_recording" => "Access recording",
    "empty_title" => "No access recordings",
    "empty_subtitle" => "%{actor_type} has no direct access recordings in this workspace"
  }.freeze
  # rubocop:enable Style/FormatStringToken

  HOME_KEYS = {
    "index.title" => "Recording Studio Accessible Demo",
    "index.subtitle" => "Optional access-control addon",
    "index.snapshot_title" => "Access check snapshot",
    "index.snapshot_subtitle" => "Demo of how access works for the seeded workspace",
    "index.integration_mode" => "Integration mode:",
    "index.workspace" => "Workspace:",
    "index.root_recording" => "Root recording:",
    "index.not_available" => "Not available",
    "overview.title" => "Overview",
    "overview.subtitle" => "How access is structured",
    "overview.add_access_title" => "Add access to something",
    "overview.add_access_subtitle" => "Access is granted by adding a child recording using an access recordable.",
    "methods.title" => "Methods",
    "methods.subtitle" => "Access APIs provided by this gem",
    "user_invites.title" => "User invites",
    "user_invites.subtitle" => "How missing emails are resolved during access grants",
    "user_invites.missing_user_title" => "What happens when a user is not found",
    "user_invites.default_badge" => "Default",
    "user_invites.default_body" => "If you do nothing, an unknown email returns unresolved. The access page stores an AccessInvitation and sends the invitation. It does not create a user.",
    "user_invites.dummy_badge" => "Dummy app",
    "user_invites.dummy_body" => "This dummy app leaves the invitation in place until the signup page creates the user and accepts.",
    "user_invites.statuses_title" => "Statuses you can return",
    "user_invites.setup_patterns_title" => "Setup patterns",
    "user_invites.setup_patterns_subtitle" => "Choose one handler shape based on what your host app should do next",
    "email_template.title" => "Email template",
    "email_template.subtitle" => "Default message sent when access is granted",
    "email_template.message_details_title" => "Message details",
    "email_template.message_details_subtitle" => "Headers used by the default mailer",
    "email_template.html_preview_title" => "HTML preview",
    "email_template.html_preview_subtitle" => "Rendered from the default HTML email template",
    "email_template.html_preview_iframe" => "HTML email preview",
    "email_template.text_preview_title" => "Text preview",
    "email_template.text_preview_subtitle" => "Plain-text fallback from the default email template"
  }.freeze

  def test_engine_ships_only_english_locale_files
    files = Dir[File.join(engine_locales_dir, "*")].map { |path| File.basename(path) }

    assert_equal ["en.yml"], files.sort
  end

  def test_rails_i18n_load_path_includes_the_gem_english_locale_file
    locale_path = File.join(engine_locales_dir, "en.yml")

    assert_includes I18n.load_path.map { |path| File.expand_path(path) }, File.expand_path(locale_path)
  end

  def test_dummy_french_covers_every_engine_english_key
    english = flatten_keys(locale_tree(File.join(engine_locales_dir, "en.yml"), "en"))
    french = flatten_keys(locale_tree(File.join(dummy_locales_dir, "fr.yml"), "fr"))
    missing = english - french

    assert_empty missing, "dummy fr.yml is missing keys present in engine en.yml: #{missing.join(', ')}"
  end

  def test_english_default_copy_is_unchanged
    I18n.with_locale(:en) do
      assert_equal "Manage access", Copy.t("manage.title")
      assert_equal "Add access", Copy.t("manage.add")
      assert_equal "Pending invitation", Copy.t("manage.pending_invitation")
      assert_equal "Accept invitation", Copy.t("invitations.accept")
      assert_equal "Access granted.", Copy.t("flashes.access_granted")
      assert_equal "Invitation sent.", Copy.t("flashes.invitation_sent")
      assert_equal "Access removed.", Copy.t("flashes.access_removed")
      assert_equal "Invitation was not found", Copy.t("errors.invitation_not_found")
      assert_equal "You were invited", Copy.t("mailers.invitation.subject")
      assert_equal "You were given access", Copy.t("mailers.granted.subject")
      assert_equal "Someone", Copy.t("mailers.someone")
      assert_equal "Unknown actor", Copy.t("errors.unknown_actor")
      assert_equal "View", Copy.role_name("view")
      assert_equal "pending", Copy.invitation_state("pending")
    end
  end

  def test_english_actor_access_points_and_home_copy_is_unchanged
    I18n.with_locale(:en) do
      assert_equal "admin@example.com access points",
                   Copy.t("actor_access_points.title", actor: "admin@example.com")
      assert_equal "Workspace: Demo", Copy.t("actor_access_points.workspace", name: "Demo")
      assert_equal "Access point", Copy.t("actor_access_points.columns.access_point")
      assert_equal "No access recordings", Copy.t("actor_access_points.empty_title")
      assert_equal "User has no direct access recordings in this workspace",
                   Copy.t("actor_access_points.empty_subtitle", actor_type: "User")
      assert_equal "Recording Studio Accessible Demo", Copy.t("home.index.title")
      assert_equal "Optional access-control addon", Copy.t("home.index.subtitle")
      assert_equal "Overview", Copy.t("home.overview.title")
      assert_equal "Methods", Copy.t("home.methods.title")
      assert_equal "User invites", Copy.t("home.user_invites.title")
      assert_equal "Email template", Copy.t("home.email_template.title")
      assert_equal "HTML email preview", Copy.t("home.email_template.html_preview_iframe")
    end
  end

  def test_actor_access_points_and_home_keys_resolve_to_literal_english
    I18n.with_locale(:en) do
      ACTOR_ACCESS_POINTS_KEYS.each do |key, english|
        full_key = "recording_studio.accessible.actor_access_points.#{key}"
        translation = I18n.t(full_key, default: nil)

        assert_equal english, translation, "#{full_key} should resolve to #{english.inspect}"
      end

      HOME_KEYS.each do |key, english|
        full_key = "recording_studio.accessible.home.#{key}"
        translation = I18n.t(full_key, default: nil)

        assert_equal english, translation, "#{full_key} should resolve to #{english.inspect}"
      end
    end
  end

  def test_role_names_fall_back_to_humanize_for_custom_roles
    I18n.with_locale(:en) do
      assert_equal "Approver", Copy.role_name("approver")
      assert_equal "Download", Copy.role_name("download")
    end
  end

  def test_component_text_overrides_win_including_nil
    assert_equal "Manage access", Copy.value(Copy::UNSET, "manage.title")
    assert_equal "Acme access", Copy.value("Acme access", "manage.title")
    assert_nil Copy.value(nil, "manage.title")
  end

  def test_defaulted_follows_locale_until_the_host_changes_the_string
    I18n.with_locale(:en) do
      assert_equal "Manage access", Copy.defaulted("Manage access", "Manage access", "manage.title")
      assert_equal "Acme access", Copy.defaulted("Acme access", "Manage access", "manage.title")
      assert_equal "Manage access", Copy.defaulted(nil, "Manage access", "manage.title")
    end
  end

  def test_html_mailer_keys_escape_interpolations_and_mark_html_safe
    html = Copy.t("mailers.invitation.body_html", inviter: "<script>x</script>", role: "view", recording: "Acme")

    assert_predicate html, :html_safe?
    assert_includes html, "<strong>view</strong>"
    refute_includes html, "<script>"
    assert_includes html, "&lt;script&gt;x&lt;/script&gt;"
  end

  def test_host_translation_overrides_english
    I18n.backend.store_translations(:en, acme_title)
    assert_equal "Acme access", Copy.t("manage.title")
  ensure
    I18n.backend.store_translations(:en, default_title)
  end

  def test_gemspec_does_not_depend_on_internationalization
    gemspec = File.read(File.expand_path("../recording_studio_accessible.gemspec", __dir__))

    refute_includes gemspec, "recording_studio_internationalization"
    refute_includes gemspec, "RecordingStudio_Internationalization"
  end

  def test_default_subjects_follow_the_locale
    I18n.available_locales = Array(I18n.available_locales) | %i[en fr]
    I18n.backend.store_translations(:fr, french_subjects)
    configuration = RecordingStudioAccessible::Configuration.new

    I18n.with_locale(:fr) do
      assert_equal "Vous avez été invité",
                   configuration.access_invitation_subject_for(
                     controller: nil, recording: nil, email: "a@example.com", role: "view", manager_actor: nil
                   )
      assert_equal "On vous a donné accès",
                   configuration.access_granted_subject_for(
                     controller: nil, recording: nil, actor: nil, role: "view", manager_actor: nil
                   )
    end
  end

  def test_access_notification_locale_defaults_to_current_and_honours_host_callable
    configuration = RecordingStudioAccessible::Configuration.new

    I18n.with_locale(:en) do
      assert_equal :en, configuration.access_notification_locale_for(email: "a@example.com")
    end

    configuration.access_notification_locale = ->(**) { :fr }

    assert_equal :fr, configuration.access_notification_locale_for(email: "a@example.com")
  end

  def test_config_callables_still_override_locale_defaults
    configuration = RecordingStudioAccessible::Configuration.new
    configuration.access_invitation_subject = ->(**) { "Host invite subject" }
    configuration.access_management_access_granted_subject = ->(**) { "Host granted subject" }
    configuration.access_management_actor_label = ->(_actor) { "Host person" }

    I18n.with_locale(:en) do
      assert_equal "Host invite subject",
                   configuration.access_invitation_subject_for(
                     controller: nil, recording: nil, email: "a@example.com", role: "view", manager_actor: nil
                   )
      assert_equal "Host granted subject",
                   configuration.access_granted_subject_for(
                     controller: nil, recording: nil, actor: nil, role: "view", manager_actor: nil
                   )
      assert_equal "Host person", configuration.actor_label_for(:anyone)
    end
  end

  private

  def engine_locales_dir
    File.expand_path("../config/locales", __dir__)
  end

  def dummy_locales_dir
    File.expand_path("dummy/config/locales", __dir__)
  end

  def locale_tree(path, locale)
    yaml = YAML.safe_load_file(path, aliases: true)
    yaml.fetch(locale).fetch("recording_studio").fetch("accessible")
  end

  def flatten_keys(hash, prefix = [])
    hash.flat_map do |key, value|
      path = prefix + [key.to_s]
      value.is_a?(Hash) ? flatten_keys(value, path) : [path.join(".")]
    end
  end

  def acme_title
    { recording_studio: { accessible: { manage: { title: "Acme access" } } } }
  end

  def default_title
    { recording_studio: { accessible: { manage: { title: "Manage access" } } } }
  end

  def french_subjects
    {
      recording_studio: {
        accessible: {
          mailers: {
            invitation: { subject: "Vous avez été invité" },
            granted: { subject: "On vous a donné accès" }
          }
        }
      }
    }
  end
end
