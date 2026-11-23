# frozen_string_literal: true

return unless defined?(RecordingStudioMcp)

RecordingStudioMcp.configure do |config|
  config.mcp_mount_path = "/recording_studio_mcp"
  config.oauth_protected_resource_path = "/.well-known/oauth-protected-resource/recording_studio_mcp"
  config.oauth_engine_mount_path = "/recording_studio_oauth"
end

Rails.application.config.to_prepare do
  RecordingStudioAccessible::McpCopy.register!
  RecordingStudioMcp.register_server(:public, api: :public) do
    include_tools(*RecordingStudioAccessible::McpCopy.tool_names)
  end
end
