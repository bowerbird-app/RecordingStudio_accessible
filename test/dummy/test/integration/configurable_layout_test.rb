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
    @previous_core_layout = RecordingStudio.configuration.layout
  end

  teardown do
    RecordingStudioAccessible.configuration.layout = @previous_layout
    RecordingStudio.configuration.layout = @previous_core_layout
  end

  test "default layout is the recording studio shell for manage access and docs" do
    assert_nil RecordingStudioAccessible.configuration.layout

    sign_in @admin

    get root_recording_accesses_path

    assert_response :success
    assert_select "body[data-recording-studio-default-layout='true']", count: 1
    assert_select "h1", text: "Manage access", count: 1
    assert_includes @response.body, "+ Access"
    refute_includes @response.body, "Main navigation"

    get "/recording_studio_accessible"

    assert_response :success
    assert_select "body[data-recording-studio-default-layout='true']", count: 1
    assert_select "h1", text: "Recording Studio Accessible Demo", count: 1
    refute_includes @response.body, "Main navigation"
  end

  test "the core layout applies when the accessible layout is nil" do
    assert_nil RecordingStudioAccessible.configuration.layout
    RecordingStudio.configuration.layout = "application"
    sign_in @admin

    get root_recording_accesses_path

    assert_response :success
    assert_includes @response.body, "Manage access"
    assert_includes @response.body, 'content="Dummy"'
    assert_select "body[data-recording-studio-default-layout]", count: 0
  end

  test "a layout name wraps an allowed actor and still denies an actor with no access" do
    RecordingStudioAccessible.configuration.layout = "flat_pack_sidebar"
    sign_in @admin

    get root_recording_accesses_path

    assert_response :success
    assert_includes @response.body, "Manage access"
    assert_includes @response.body, "Main navigation"
    assert_select "body[data-recording-studio-default-layout]", count: 0

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

  test "a false layout renders the screen without a document layout" do
    RecordingStudioAccessible.configuration.layout = false
    RecordingStudio.configuration.layout = "recording_studio/default_layout"
    sign_in @admin

    get root_recording_accesses_path

    assert_response :success
    assert_includes @response.body, "layout-admin@example.com"
    assert_includes @response.body, "Who"
    refute_includes @response.body, "People with access"
    refute_match(/<html/i, @response.body)
    assert_select "body[data-recording-studio-default-layout]", count: 0
  end

  test "a layout callable that returns a non-layout raises" do
    RecordingStudioAccessible.configuration.layout = ->(controller:) { 1 }
    sign_in @admin

    error = assert_raises(ArgumentError) { get root_recording_accesses_path }

    assert_match "layout callable must return", error.message
  end

  test "a layout callable that raises still denies an actor with no access" do
    calls = 0
    RecordingStudioAccessible.configuration.layout = lambda do |**|
      calls += 1
      raise "layout failed closed"
    end
    sign_in @outsider

    get root_recording_accesses_path

    assert_response :forbidden
    assert_equal 0, calls
    refute_includes @response.body, "layout failed closed"
    refute_includes @response.body, "Manage access"
  end

  test "a layout callable that raises is not used for an access request modal" do
    calls = 0
    RecordingStudioAccessible.configuration.layout = lambda do |**|
      calls += 1
      raise "layout failed closed"
    end

    get "/recording_studio_accessible/recordings/#{@root_recording.id}/access_requests/new",
        params: { presentation: "modal" },
        headers: { "Turbo-Frame" => "access_request" }

    assert_response :success
    assert_equal 0, calls
    assert_select "turbo-frame#access_request"
    assert_select "h1", text: "Request access"
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
