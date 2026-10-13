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

  test "macro defines prefixed delegators and helper_method for current root" do
    assert ControllerAuthDemosController.method_defined?(:authenticate_demo_actor!)
    assert ControllerAuthDemosController.method_defined?(:demo_actor)
    assert ControllerAuthDemosController.method_defined?(:current_demo_root)
    assert ControllerAuthDemosController.method_defined?(:set_demo_current_actor)
    assert_includes ControllerAuthDemosController._helper_methods.map(&:to_s), "current_demo_root"
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
end
