# frozen_string_literal: true

require "test_helper"

class AccessNamedMcpToolsTest < ActionDispatch::IntegrationTest
  WORKSPACE_TOOLS = %w[
    list_access_to_workspace
    grant_access_to_workspace
    update_access_to_workspace
    revoke_access_to_workspace
  ].freeze
  PRESS_KIT_TOOLS = %w[
    list_access_to_press_kit
    grant_access_to_press_kit
    update_access_to_press_kit
    revoke_access_to_press_kit
  ].freeze
  LEGACY_TOOL_NAMES = %w[
    grant_access
    list_access
    update_access
    revoke_access
    capability_action
    Workspace--grant_access
    grant_access_to_page
    list_access_to_page
  ].freeze

  setup do
    skip "Recording Studio MCP is not loaded" unless defined?(RecordingStudioMcp)

    @admin = create_user("mcp-access-admin-#{SecureRandom.hex(3)}@example.com")
    @editor = create_user("mcp-access-editor-#{SecureRandom.hex(3)}@example.com")
    @stranger = create_user("mcp-access-stranger-#{SecureRandom.hex(3)}@example.com")
    @invitee = create_user("mcp-access-invitee-#{SecureRandom.hex(3)}@example.com")
    @workspace = Workspace.create!(name: "MCP access #{SecureRandom.hex(3)}")
    @root = create_root_recording(@workspace)
    @admin_access = create_direct_access_recording(actor: @admin, role: :admin, parent_recording: @root)
    @editor_access = create_direct_access_recording(actor: @editor, role: :edit, parent_recording: @root)
    create_direct_access_recording(actor: @invitee, role: :view, parent_recording: @root)

    @other = Workspace.create!(name: "MCP other #{SecureRandom.hex(3)}")
    @other_root = create_root_recording(@other)
    @stranger_access = create_direct_access_recording(actor: @stranger, role: :admin, parent_recording: @other_root)

    @admin_token = token_for(@admin_access, "admin", manager: @admin)
    @editor_token = token_for(@editor_access, "editor", manager: @admin)
    @stranger_token = token_for(@stranger_access, "stranger", manager: @stranger)
  end

  test "named tools are listed and the old generic names are not" do
    listed = rpc(@admin_token, "tools/list")
    names = listed.dig("result", "tools").map { |tool| tool.fetch("name") }

    WORKSPACE_TOOLS.each { |name| assert_includes names, name }
    PRESS_KIT_TOOLS.each { |name| assert_includes names, name }
    %w[grant_access_to_folder grant_access_to_message_group].each { |name| assert_includes names, name }
    LEGACY_TOOL_NAMES.each { |name| refute_includes names, name }
    refute_includes names, "grant_access_to_staff_root"
    refute_includes RecordingStudioAccessible::McpCopy.accessible_types, "Page"
    refute_includes RecordingStudioAccessible::McpCopy.accessible_types, "StaffRoot"

    press_kit = RecordingStudioMcp.configuration.tool("grant_access_to_press_kit")
    assert_equal "PressKit", press_kit.type
    assert_nil RecordingStudioMcp.configuration.tool("grant_access")

    grant = listed.dig("result", "tools").find { |tool| tool.fetch("name") == "grant_access_to_press_kit" }
    assert_includes grant.fetch("description"), "must already exist"
    refute_match(/\b(?:view|edit|admin)\b/i, grant.fetch("description"))
    tags = RecordingStudioMcp::ToolDocs.action_tags(
      "PressKit",
      api: :public,
      tag_suffix: RecordingStudioMcp::Documentation::Openapi::ActionDocs.tag_suffix(:grant_access, :public, "PressKit")
    )
    assert_equal [ "PressKit" ], tags
    refute_includes tags, "Access"
  end

  test "list_access allows an admin and denies a lower role and a stranger" do
    allowed = call_tool(@admin_token, "list_access")
    refute allowed.dig("result", "isError"), allowed.to_json
    labels = payload(allowed).fetch("grants").filter_map { |row| row.dig("actor", "label") }
    assert_includes labels, @admin.email

    assert_denied(@editor_token, "list_access")
    assert_denied(@stranger_token, "list_access")
  end

  test "grant_access allows an admin and denies a lower role and a stranger" do
    person = create_user("mcp-access-granted-#{SecureRandom.hex(3)}@example.com")
    arguments = { actor_id: person.id.to_s, actor_type: "User", role: "view" }

    assert_denied(@editor_token, "grant_access", arguments)
    assert_denied(@stranger_token, "grant_access", arguments)
    refute RecordingStudioAccessible.authorized?(actor: person, recording: @root, role: :view)

    allowed = call_tool(@admin_token, "grant_access", arguments)
    refute allowed.dig("result", "isError"), allowed.to_json
    assert RecordingStudioAccessible.authorized?(actor: person, recording: @root, role: :view)
  end

  test "update_access allows an admin and denies a lower role and a stranger" do
    arguments = { actor_id: @invitee.id.to_s, actor_type: "User", role: "edit" }

    assert_denied(@editor_token, "update_access", arguments)
    assert_denied(@stranger_token, "update_access", arguments)
    assert_equal :view, RecordingStudioAccessible.role_for(actor: @invitee, recording: @root)

    allowed = call_tool(@admin_token, "update_access", arguments)
    refute allowed.dig("result", "isError"), allowed.to_json
    assert_equal :edit, RecordingStudioAccessible.role_for(actor: @invitee, recording: @root)
  end

  test "revoke_access allows an admin and denies a lower role and a stranger" do
    arguments = { actor_id: @invitee.id.to_s, actor_type: "User" }

    assert_denied(@editor_token, "revoke_access", arguments)
    assert_denied(@stranger_token, "revoke_access", arguments)
    assert RecordingStudioAccessible.authorized?(actor: @invitee, recording: @root, role: :view)

    allowed = call_tool(@admin_token, "revoke_access", arguments)
    refute allowed.dig("result", "isError"), allowed.to_json
    refute RecordingStudioAccessible.authorized?(actor: @invitee, recording: @root, role: :view)
  end

  test "a grant with missing input is a tool error" do
    denied = call_tool(@admin_token, "grant_access", {})

    assert denied.dig("result", "isError"), denied.to_json
  end

  private

  def call_tool(token, action, arguments = {})
    rpc(
      token,
      "tools/call",
      name: "#{action}_to_workspace",
      arguments: arguments.merge(id: @root.id.to_s)
    )
  end

  def assert_denied(token, name, arguments = {})
    result = call_tool(token, name, arguments)
    assert result.dig("result", "isError"), result.to_json
  end

  def payload(body)
    structured = body.dig("result", "structuredContent")
    return structured if structured.is_a?(Hash) && structured.key?("grants")

    JSON.parse(body.dig("result", "content", 0, "text").to_s)
  end

  def rpc(token, method, **params)
    post "/recording_studio_mcp",
         params: { jsonrpc: "2.0", id: SecureRandom.random_number(1_000), method: method, params: params }.to_json,
         headers: {
           "Content-Type" => "application/json",
           "Accept" => "application/json",
           "Authorization" => "Bearer #{token}"
         }
    assert_response :success, response.body
    JSON.parse(response.body)
  end

  def token_for(access_recording, name, manager:)
    previous_types = RecordingStudioAccessible.configuration.access_actor_types
    RecordingStudioAccessible.configuration.access_actor_types =
      Array(previous_types) | ["RecordingStudioApi::ApiClient"]

    payload = RecordingStudioAccessible::AccessCreationContext.allow do
      result = RecordingStudioApi::Services::ProvisionApiClient.call(
        access_point_recording: access_recording.parent_recording || access_recording.root_recording,
        manager_actor: manager,
        role: access_recording.recordable.role,
        name: "mcp-access-#{name}-#{SecureRandom.hex(3)}"
      )
      raise result.error unless result.success?

      result.value
    end

    token_result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: payload.fetch(:credential).oauth_client_id,
      client_secret: payload.fetch(:token)
    )
    raise token_result.error unless token_result.success?

    token_result.value.fetch(:access_token)
  ensure
    RecordingStudioAccessible.configuration.access_actor_types = previous_types
  end

  def create_user(email)
    User.create!(email: email, password: "Password", password_confirmation: "Password")
  end
end
