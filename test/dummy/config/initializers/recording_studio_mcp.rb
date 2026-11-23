# frozen_string_literal: true

return unless defined?(RecordingStudioMcp)

RecordingStudioMcp.configure do |config|
  config.mcp_mount_path = "/recording_studio_mcp"
  config.oauth_protected_resource_path = "/.well-known/oauth-protected-resource/recording_studio_mcp"
  config.oauth_engine_mount_path = "/recording_studio_oauth"
end

RecordingStudioMcp.register_type(
  type: "Workspace",
  description: "Workspace records nest by parent_id. Call describe before you write."
)

Rails.application.config.to_prepare do
  RecordingStudioAccessible::McpCopy.register!
  RecordingStudioMcp.register_server(:public, api: :public) do
    # list and show put Workspace on the server. Typeless access tools use that type list.
    include_tools(:list, :show, *RecordingStudioAccessible::McpCopy.tool_names)
  end
end
