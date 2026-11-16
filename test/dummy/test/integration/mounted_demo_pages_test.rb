# frozen_string_literal: true

require_relative "../test_helper"

class MountedDemoPagesTest < ActionDispatch::IntegrationTest
  MOUNTED_PAGES = [
    "/recording_studio_accessible",
    "/recording_studio_accessible/overview",
    "/recording_studio_accessible/methods",
    "/recording_studio_accessible/user_invites",
    "/recording_studio_accessible/email_template"
  ].freeze

  setup do
    @configuration = RecordingStudioAccessible.configuration
    @original_resolver = @configuration.admin_root_resolver
    @original_authorizer = @configuration.mounted_page_authorizer
    @original_actor_resolver = @configuration.access_management_current_actor_resolver

    @outsider = create_user("first-owner@example.com")
    @leaked = create_user("aaa-leaked@example.com")
    @named_admin = create_user("admin@admin.com")
    @named_viewer = create_user("viewer@admin.com")
    @staff = create_user("staff-gate@example.com")

    first_workspace = Workspace.create!(name: "000 First workspace")
    @first_root = create_root_recording(first_workspace)
    grant_access(@outsider, :admin, @first_root)
    grant_access(@staff, :admin, @first_root)

    staff_workspace = Workspace.create!(name: "Staff gate workspace")
    @staff_root = create_root_recording(staff_workspace)
    grant_access(@staff, :admin, @staff_root)

    @configuration.admin_root_resolver = -> { @staff_root }
  end

  teardown do
    @configuration.admin_root_resolver = @original_resolver
    @configuration.mounted_page_authorizer = @original_authorizer
    @configuration.access_management_current_actor_resolver = @original_actor_resolver
  end

  test "a non-staff user who owns the first workspace is denied on every demo page" do
    sign_in @outsider

    MOUNTED_PAGES.each do |path|
      get path

      assert_response :redirect, path
      assert_redirected_to "/"
    end
  end

  test "an admin on the admin root can open every demo page" do
    sign_in @staff

    MOUNTED_PAGES.each do |path|
      get path

      assert_response :success, path
    end
  end

  test "index and email preview omit real people and real workspaces" do
    sign_in @staff

    get "/recording_studio_accessible/email_template"

    assert_response :success
    assert_real_records_absent
    assert_includes @response.body, "admin@example.com"
    assert_includes @response.body, "viewer@example.com"
    assert_includes @response.body, "Sample workspace"
    assert_includes @response.body, "https://example.com/sample"
    refute_includes @response.body, "000 First workspace"
    refute_includes @response.body, "Staff gate workspace"

    get "/recording_studio_accessible"

    assert_response :success
    assert_real_records_absent
    assert_includes @response.body, "admin@example.com"
    assert_includes @response.body, "viewer@example.com"
    refute_includes @response.body, "000 First workspace"
    refute_includes @response.body, "Staff gate workspace"
  end

  test "a nil actor is denied" do
    @configuration.access_management_current_actor_resolver = ->(**) {}
    sign_in @staff

    get "/recording_studio_accessible"

    assert_response :redirect
    assert_redirected_to "/"
  end

  test "a missing admin root denies the request" do
    @configuration.admin_root_resolver = nil
    sign_in @staff

    get "/recording_studio_accessible"

    assert_response :redirect
    assert_redirected_to "/"
  end

  test "a host mounted page authorizer replaces the default" do
    @configuration.mounted_page_authorizer = lambda do |actor:, **|
      actor == @outsider
    end

    sign_in @outsider
    get "/recording_studio_accessible"
    assert_response :success

    sign_in @staff
    get "/recording_studio_accessible"
    assert_response :redirect
    assert_redirected_to "/"
  end

  private

  def assert_real_records_absent
    [ @outsider.email, @leaked.email, @named_admin.email, @named_viewer.email, @staff.email ].each do |email|
      refute_includes @response.body, email
    end
  end

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def grant_access(user, role, parent_recording)
    create_direct_access_recording(actor: user, role: role, parent_recording: parent_recording)
  end
end
