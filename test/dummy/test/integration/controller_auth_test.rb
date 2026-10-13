# frozen_string_literal: true

require_relative "../test_helper"

class ControllerAuthTest < ActionDispatch::IntegrationTest
  setup do
    ControllerAuthDemoConfig.reset!
    @admin = User.find_by(email: "admin@admin.com") ||
             User.create!(email: "admin@admin.com", password: "Password", password_confirmation: "Password")
    @viewer = User.find_by(email: "viewer-auth@example.com") ||
              User.create!(email: "viewer-auth@example.com", password: "Password", password_confirmation: "Password")

    @workspace = Workspace.create!(name: "Controller Auth Workspace #{SecureRandom.hex(4)}")
    @root_recording = create_root_recording(@workspace)
    create_direct_access_recording(actor: @admin, role: :admin, parent_recording: @root_recording)
    create_direct_access_recording(actor: @viewer, role: :view, parent_recording: @root_recording)
  end

  teardown do
    ControllerAuthDemoConfig.reset!
  end

  test "macro defines private prefixed helpers and helper_method for current root" do
    assert ControllerAuthDemosController.private_method_defined?(:authenticate_demo_actor!)
    assert ControllerAuthDemosController.private_method_defined?(:demo_actor)
    assert ControllerAuthDemosController.private_method_defined?(:current_demo_root)
    assert ControllerAuthDemosController.private_method_defined?(:set_demo_current_actor)
    assert_includes ControllerAuthDemosController._helper_methods.map(&:to_s), "current_demo_root"
  end

  test "action_methods excludes generated auth helpers" do
    methods = ControllerAuthDemosController.action_methods

    refute_includes methods, "authenticate_demo_actor!"
    refute_includes methods, "demo_actor"
    refute_includes methods, "current_demo_root"
    refute_includes methods, "set_demo_current_actor"
  end

  test "recording_studio_auth class attributes are class-only readers" do
    assert ControllerAuthDemosController.respond_to?(:recording_studio_auth_options)
    refute ControllerAuthDemosController.new.respond_to?(:recording_studio_auth_options)
    assert ControllerAuthDemosController.recording_studio_auth_options.frozen?
  end

  test "authenticate_recording_studio_actor! uses configuration authentication_method" do
    sign_in @admin

    get controller_auth_demo_path

    assert_response :success
    assert_match(/actor=#{Regexp.escape(@admin.email)}/, response.body)
    assert_match(/current_actor=#{Regexp.escape(@admin.email)}/, response.body)
  end

  test "authenticate_recording_studio_actor! returns unauthorized when no authentication_method" do
    ControllerAuthDemoConfig.authentication_method = nil

    get controller_auth_demo_path

    assert_response :unauthorized
  end

  test "recording_studio_actor prefers Current.actor then current_actor_method" do
    sign_in @admin

    get controller_auth_demo_path, params: { plant_actor_email: @viewer.email }

    assert_response :success
    assert_match(/actor=#{Regexp.escape(@viewer.email)}/, response.body)
    assert_match(/current_actor=#{Regexp.escape(@viewer.email)}/, response.body)
  end

  test "recording_studio_actor ignores blank Current.actor via presence" do
    sign_in @admin

    get controller_auth_demo_path, params: { plant_blank_current_actor: "1" }

    assert_response :success
    assert_match(/actor=#{Regexp.escape(@admin.email)}/, response.body)
  end

  test "set Current.actor before_action assigns the resolved actor" do
    sign_in @admin
    Current.reset if Current.respond_to?(:reset)

    get controller_auth_demo_path

    assert_response :success
    assert_match(/current_actor=#{Regexp.escape(@admin.email)}/, response.body)
  end

  test "authorize_recording! returns unauthorized when there is no actor" do
    ControllerAuthDemoConfig.authentication_method = :allow_without_actor!
    ControllerAuthDemoConfig.current_actor_method = nil

    get authorize_controller_auth_demo_path, params: { recording_id: @root_recording.id, role: "view" }

    assert_response :unauthorized
  end

  test "authorize_recording! returns forbidden when the actor is not authorized" do
    stranger = User.create!(
      email: "stranger-auth@example.com",
      password: "Password",
      password_confirmation: "Password"
    )
    sign_in stranger

    get authorize_controller_auth_demo_path, params: { recording_id: @root_recording.id, role: "view" }

    assert_response :forbidden
  end

  test "authorize_recording! allows an authorized actor" do
    sign_in @viewer

    get authorize_controller_auth_demo_path, params: { recording_id: @root_recording.id, role: "view" }

    assert_response :success
    assert_equal "authorized", response.body
  end

  test "authorize_recording! forbids a higher role the actor does not have" do
    sign_in @viewer

    get authorize_controller_auth_demo_path, params: { recording_id: @root_recording.id, role: "admin" }

    assert_response :forbidden
  end

  test "authorize_recording! forbids a nil recording" do
    sign_in @admin

    get authorize_nil_recording_controller_auth_demo_path

    assert_response :forbidden
  end

  test "current_recording_studio_root uses current_root_recording when present" do
    sign_in @admin

    get controller_auth_demo_path, params: { root_recording_id: @root_recording.id }

    assert_response :success
    assert_match(/root=#{@root_recording.id}/, response.body)
  end

  test "require_root! returns forbidden when no root is selected" do
    sign_in @admin

    get require_root_controller_auth_demo_path

    assert_response :forbidden
  end

  test "require_root! allows a selected root" do
    sign_in @admin

    get require_root_controller_auth_demo_path, params: { root_recording_id: @root_recording.id }

    assert_response :success
    assert_equal "root=#{@root_recording.id}", response.body
  end

  test "custom options change missing-actor status, root status, and plain responses" do
    ControllerAuthDemoConfig.authentication_method = :allow_without_actor!
    ControllerAuthDemoConfig.current_actor_method = nil

    get authorize_controller_auth_custom_demo_path, params: { recording_id: @root_recording.id }

    assert_response :forbidden
    assert_equal "no actor", response.body
  end

  test "custom options skip setting Current.actor and use method_only resolution" do
    sign_in @admin

    get controller_auth_custom_demo_path, params: { plant_actor_email: @viewer.email }

    assert_response :success
    assert_match(/actor=#{Regexp.escape(@admin.email)}/, response.body)
    assert_match(/current_actor=#{Regexp.escape(@viewer.email)}/, response.body)
  end

  test "custom options use missing_root_status for require_root!" do
    sign_in @admin

    get require_root_controller_auth_custom_demo_path

    assert_response :not_found
    assert_equal "pick a workspace", response.body
  end

  test "host override of authenticate_<prefix>_actor! is honored" do
    get controller_auth_override_demo_path
    assert_response :unauthorized

    get controller_auth_override_demo_path, params: { token: "demo-token" }
    assert_response :success
    assert_equal "actor=#{@admin.email}", response.body
  end

  test "site_settings method names and configured_as_is keep a nil configured actor" do
    ControllerAuthDemoConfig.authentication_method = :allow_without_actor!
    ControllerAuthDemoConfig.current_actor_method = :nil_configured_actor

    ControllerAuthSiteSettingsDemosController.class_eval do
      def nil_configured_actor
        nil
      end
      private :nil_configured_actor
    end

    get controller_auth_site_settings_demo_path

    assert_response :success
    assert_match(/actor=$/, response.body.split(" ").first)
  ensure
    ControllerAuthSiteSettingsDemosController.class_eval do
      remove_method :nil_configured_actor if method_defined?(:nil_configured_actor) ||
                                            private_method_defined?(:nil_configured_actor)
    end
  end

  test "site_settings renamed helpers are private and excluded from action_methods" do
    methods = ControllerAuthSiteSettingsDemosController.action_methods

    assert ControllerAuthSiteSettingsDemosController.private_method_defined?(
      :authenticate_recording_studio_site_settings!
    )
    assert ControllerAuthSiteSettingsDemosController.private_method_defined?(:set_current_actor)
    assert ControllerAuthSiteSettingsDemosController.private_method_defined?(:current_actor)
    refute_includes methods, "authenticate_recording_studio_site_settings!"
    refute_includes methods, "set_current_actor"
    refute_includes methods, "current_actor"
  end

  test "stripe authenticate false require_actor redirects when signed out" do
    get controller_auth_stripe_demo_path

    assert_redirected_to new_user_session_path
    assert_equal "sign in", flash[:alert]
  end

  test "stripe require_root! returns plain not_found when signed in without a root" do
    sign_in @admin

    get controller_auth_stripe_demo_path

    assert_response :not_found
    assert_equal "pick a workspace", response.body
  end

  test "stripe actor_resolver and root_resolver succeed together" do
    sign_in @admin

    get controller_auth_stripe_demo_path, params: { root_recording_id: @root_recording.id }

    assert_response :success
    assert_equal "root=#{@root_recording.id} actor=#{@admin.email}", response.body
  end

  test "macro rejects a second configuration" do
    error = assert_raises(ArgumentError) do
      ControllerAuthDemosController.recording_studio_auth(
        config: -> { ControllerAuthDemoConfig },
        prefix: :again
      )
    end
    assert_match(/already configured/, error.message)
  end

  test "macro rejects an invalid prefix" do
    error = assert_raises(ArgumentError) do
      Class.new(ActionController::Base) do
        include RecordingStudioAccessible::ControllerAuth
        recording_studio_auth(config: -> { ControllerAuthDemoConfig }, prefix: "Bad-Prefix")
      end
    end
    assert_match(/prefix:/, error.message)
  end

  test "macro rejects an invalid actor_resolution" do
    error = assert_raises(ArgumentError) do
      Class.new(ActionController::Base) do
        include RecordingStudioAccessible::ControllerAuth
        recording_studio_auth(
          config: -> { ControllerAuthDemoConfig },
          prefix: :mutation,
          actor_resolution: :not_a_real_mode
        )
      end
    end
    assert_match(/actor_resolution:/, error.message)
  end
end
