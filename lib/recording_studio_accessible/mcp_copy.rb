# frozen_string_literal: true

require_relative "mcp_copy/copy"

module RecordingStudioAccessible
  # Registers access tools on Recording Studio MCP when that gem is loaded.
  # This gem does not depend on it. Hosts that skip MCP keep the API only.
  module McpCopy
    TOOL_NAMES = %w[list_access grant_access update_access revoke_access].freeze

    module_function

    def mcp_available?
      defined?(::RecordingStudioMcp) && ::RecordingStudioMcp.respond_to?(:register_tool)
    end

    def register!
      return unless mcp_available?

      TOOL_NAMES.each { |name| ::RecordingStudioMcp.register_tool(**tool_registration(name)) }
    end

    def tool_names
      TOOL_NAMES
    end

    def tool_registration(name)
      {
        name: name,
        action: name.to_sym,
        title: Copy::TITLES.fetch(name),
        description: Copy::DESCRIPTIONS.fetch(name),
        input: Copy::INPUTS.fetch(name),
        output: Copy::OUTPUTS.fetch(name)
      }
    end
  end
end
