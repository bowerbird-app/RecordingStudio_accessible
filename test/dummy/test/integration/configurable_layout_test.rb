# frozen_string_literal: true

require_relative "../test_helper"

class ConfigurableLayoutTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user("layout-admin@example.com")
    @outsider = create_user("layout-outsider@example.com")
    workspace = Workspace.create!(name: "000 Layout Workspace")
    @root_recording = create_root_recording(workspace)
    grant_access(@admin, :admin, @root_recording)
    @previous_layout = RecordingStudioAccessible.configuration.layout
  end

  teardown do
    RecordingStudioAccessible.configuration.layout = @previous_layout
  end

  test "default layout stays the blank engine layout for manage access and the host layout for docs" do
    assert_nil RecordingStudioAccessible.configuration.layout

    sign_in @admin

    get root_recording_accesses_path

    assert_response :success
    assert_includes @response.body, "Manage access"
    assert_includes @response.body, 'content="Recording Studio Accessible"'
    refute_includes @response.body, "Main navigation"

    get "/recording_studio_accessible"

    assert_response :success
    assert_includes @response.body, "Main navigation"
  end

  test "a layout name wraps an allowed actor and still denies an actor with no access" do
    RecordingStudioAccessible.configuration.layout = "flat_pack_sidebar"
    sign_in @admin

    get root_recording_accesses_path

    assert_response :success
    assert_includes @response.body, "Manage access"
    assert_includes @response.body, "Main navigation"

    sign_in @outsider

    get root_recording_accesses_path

    assert_response :forbidden
    refute_includes @response.body, "Manage access"
  end

  test "a layout callable wraps an allowed actor" do
    RecordingStudioAccessible.configuration.layout = lambda do |controller:|
      raise "wrong controller" unless controller.is_a?(RecordingStudioAccessible::RecordingAccessesController)

      "application"
    end
    sign_in @admin

    get root_recording_accesses_path

    assert_response :success
    assert_includes @response.body, "Manage access"
    assert_includes @response.body, 'content="Dummy"'
    refute_includes @response.body, "Main navigation"
  end

  test "a layout callable that raises still denies an actor with no access" do
    RecordingStudioAccessible.configuration.layout = ->(**) { raise "layout failed closed" }
    sign_in @outsider

    get root_recording_accesses_path

    assert_response :forbidden
    refute_includes @response.body, "layout failed closed"
    refute_includes @response.body, "Manage access"
  end

  test "a layout callable that raises is not used for an access request modal" do
    RecordingStudioAccessible.configuration.layout = ->(**) { raise "layout failed closed" }

    get "/recording_studio_accessible/recordings/#{@root_recording.id}/access_requests/new",
        params: { presentation: "modal" },
        headers: { "Turbo-Frame" => "access_request" }

    assert_response :success
    assert_select "turbo-frame#access_request"
    refute_match(/<html/i, @response.body)
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def grant_access(user, role, parent_recording)
    create_direct_access_recording(actor: user, role: role, parent_recording: parent_recording)
  end

  def root_recording_accesses_path
    "/recording_studio_accessible/recordings/#{@root_recording.id}/accesses"
  end
end
