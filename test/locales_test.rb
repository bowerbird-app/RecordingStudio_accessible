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
    "index.admin_fallback" => "Admin",
    "index.viewer_fallback" => "Viewer",
    "index.anonymous" => "Anonymous",
    "overview.title" => "Overview",
    "overview.subtitle" => "How access is structured",
    "overview.add_access_title" => "Add access to something",
    "overview.add_access_subtitle" => "Access is granted by adding a child recording using an access recordable.",
    "methods.title" => "Methods",
    "methods.subtitle" => "Access APIs provided by this gem",
    "methods.bootstrap_title" => "Bootstrap the first owner with RecordingStudioAccessible.bootstrap_owner_access!",
    "methods.grant_title" => "Grant access with RecordingStudioAccessible.grant_access",
    "methods.role_for_title" => "Resolve a user's role with RecordingStudioAccessible.role_for",
    "methods.authorized_title" => "Check authorization with RecordingStudioAccessible.authorized?",
    "methods.root_recordings_title" => "List accessible roots with RecordingStudioAccessible.root_recordings_for",
    "methods.root_recording_ids_title" => "List accessible root ids with RecordingStudioAccessible.root_recording_ids_for",
    "methods.access_recordings_title" => "List direct grants on a recording with RecordingStudioAccessible.access_recordings_for",
    "user_invites.title" => "User invites",
    "user_invites.subtitle" => "How missing emails are resolved during access grants",
    "user_invites.missing_user_title" => "What happens when a user is not found",
    "user_invites.default_badge" => "Default",
    "user_invites.default_body" => "If you do nothing, an unknown email returns unresolved. The access page stores an AccessInvitation and sends the invitation. It does not create a user.",
    "user_invites.dummy_badge" => "Dummy app",
    "user_invites.dummy_body" => "This dummy app leaves the invitation in place until the signup page creates the user and accepts.",
    "user_invites.statuses_title" => "Statuses you can return",
    "user_invites.statuses.unresolved" => "The default when no actor matches the email. The access page stores an invitation and sends it.",
    "user_invites.statuses.found" => "An existing actor was resolved from the submitted email, so the access grant can continue immediately.",
    "user_invites.statuses.created" => "Use this only after your app has already verified the recipient and finished any setup needed for the same grant request.",
    "user_invites.statuses.invited" => "Use this when another invite flow sent the invitation. The addon stores nothing and sends the manager back to the access list with a notice.",
    "user_invites.statuses.requires_resolution" => "Redirect the manager into a setup flow, such as a custom user creation screen, before granting access.",
    "user_invites.statuses.invalid" => "The submitted email could not be used. The form re-renders with the returned error message.",
    "user_invites.setup_patterns_title" => "Setup patterns",
    "user_invites.setup_patterns_subtitle" => "Choose one handler shape based on what your host app should do next",
    "user_invites.setup.find_existing_title" => "Only find existing users",
    "user_invites.setup.find_existing_body" => "Use the resolver when your app should only grant access to users that already exist.",
    "user_invites.setup.block_until_trusted_title" => "Keep the form blocked until a trusted workflow resolves the email",
    "user_invites.setup.block_until_trusted_body" => "Prefer returning an error until your app finishes any invite, approval, or verification work for that address.",
    "user_invites.setup.redirect_resolution_title" => "Send managers to a resolution flow",
    "user_invites.setup.redirect_resolution_body" => "Return a redirect-style resolution when a person needs extra setup, approvals, or a richer invite workflow before the grant continues.",
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
    # with_gem_english_locale_only puts only en.yml on the path and reloads.
    # Assert that file actually drives lookups (not merely that the path we set is present).
    with_gem_english_locale_only do
      locale_path = File.expand_path(File.join(engine_locales_dir, "en.yml"))
      assert_equal([locale_path], I18n.load_path.map { |path| File.expand_path(path) })
      assert_equal "Manage access", I18n.t("recording_studio.accessible.manage.title")
      assert_equal "Access granted.", I18n.t("recording_studio.accessible.flashes.access_granted")
    end
  end

  def test_lib_sources_do_not_append_i18n_load_path
    lib_dir = File.expand_path("../lib", __dir__)
    ruby_files = Dir[File.join(lib_dir, "**", "*.rb")]

    refute_empty ruby_files, "expected lib/**/*.rb files to scan"

    ruby_files.each do |path|
      source = File.read(path)

      refute_includes source, "i18n.load_path", "#{path} must not touch i18n.load_path"
      refute_includes source, "I18n.load_path", "#{path} must not touch I18n.load_path"
    end
  end

  def test_dummy_french_covers_every_engine_english_key
    english = flatten_keys(locale_tree(File.join(engine_locales_dir, "en.yml"), "en"))
    french = flatten_keys(locale_tree(File.join(dummy_locales_dir, "fr.yml"), "fr"))
    missing = english - french

    assert_empty missing, "dummy fr.yml is missing keys present in engine en.yml: #{missing.join(', ')}"
  end

  def test_english_default_copy_is_unchanged
    with_gem_english_locale_only do
      I18n.with_locale(:en) do
        assert_equal "Manage access", Copy.t("manage.title")
        assert_equal "+ Access", Copy.t("manage.add")
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
        assert_equal "Recording Studio Accessible", Copy.t("layout.title")
      end
    end
  end

  def test_english_actor_access_points_and_home_copy_is_unchanged
    with_gem_english_locale_only do
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
        assert_equal "Anyone", Copy.t("audiences.public")
        assert_equal "Signed in", Copy.t("audiences.signed_in")
        assert_equal "People with access", Copy.t("audiences.granted")
        assert_equal "Grant access with RecordingStudioAccessible.grant_access",
                     Copy.t("home.methods.grant_title")
        assert_equal "Only find existing users",
                     Copy.t("home.user_invites.setup.find_existing_title")
      end
    end
  end

  def test_actor_access_points_and_home_keys_resolve_to_literal_english
    with_gem_english_locale_only do
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
  end

  def test_role_names_fall_back_to_humanize_for_custom_roles
    I18n.with_locale(:en) do
      assert_equal "Approver", Copy.role_name("approver")
      assert_equal "Download", Copy.role_name("download")
    end
  end

  def test_role_name_guards_nil_and_blank_roles
    I18n.with_locale(:en) do
      assert_equal "", Copy.role_name(nil)
      assert_equal "", Copy.role_name("")
      refute_kind_of Hash, Copy.role_name(nil)
    end
  end

  def test_role_name_uses_locale_and_falls_back_for_unknown_roles_in_non_english
    I18n.available_locales = Array(I18n.available_locales) | %i[en fr xx]
    I18n.backend.store_translations(:fr, { recording_studio: { accessible: { roles: { view: "Voir" } } } })

    I18n.with_locale(:fr) do
      assert_equal "Voir", Copy.role_name("view")
      assert_equal "Approver", Copy.role_name("approver")
    end
  ensure
    I18n.backend.store_translations(:fr, { recording_studio: { accessible: { roles: { view: "Voir" } } } })
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

  def test_grant_denied_call_time_value_follows_locale_not_the_constant
    I18n.available_locales = Array(I18n.available_locales) | %i[en fr]
    I18n.backend.store_translations(
      :fr,
      {
        recording_studio: {
          accessible: {
            errors: {
              grant_denied: "Accès refusé sur la racine partagée"
            }
          }
        }
      }
    )

    I18n.with_locale(:fr) do
      translated = Copy.t("errors.grant_denied")

      assert_equal "Accès refusé sur la racine partagée", translated
      refute_equal RecordingStudioAccessible::SharedRootAccess::GRANT_DENIED_MESSAGE, translated
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

  # Gem English assertions load only the engine en.yml. Always restore
  # I18n.load_path, then re-seed the unit-suite backend (unit tests do not put
  # gem locales on the load path).
  def with_gem_english_locale_only
    previous = I18n.load_path.dup
    I18n.load_path = [File.join(engine_locales_dir, "en.yml")]
    I18n.backend.load_translations
    yield
  ensure
    I18n.load_path = previous
    I18n.backend.load_translations
    I18n.backend.store_translations(:en, gem_english_tree)
  end

  def gem_english_tree
    YAML.safe_load_file(File.join(engine_locales_dir, "en.yml"), aliases: true).fetch("en")
  end
end
