# frozen_string_literal: true

require_relative "mcp_copy/copy"

module RecordingStudioAccessible
  # Registers one access tool per action for each API type that enables :accessible.
  # This gem does not depend on Recording Studio MCP. Hosts that skip it keep the API only.
  module McpCopy
    ACTIONS = %i[list_access grant_access update_access revoke_access].freeze

    module_function

    def mcp_available?
      defined?(::RecordingStudioMcp) && ::RecordingStudioMcp.respond_to?(:register_tool)
    end

    def register!
      return unless mcp_available?

      accessible_types.each do |type|
        register_type!(type)
        ACTIONS.each do |action|
          next unless action_enabled?(type, action)

          ::RecordingStudioMcp.register_tool(**tool_registration(action, type))
        end
      end
    end

    def tool_names
      return [] unless mcp_available?

      accessible_types.flat_map do |type|
        ACTIONS.filter_map { |action| tool_name(action, type) if action_enabled?(type, action) }
      end
    end

    def tool_name(action, type)
      "#{action}_to_#{::RecordingStudioMcp::ToolName.type_singular_snake(type)}"
    end

    def tool_registration(action, type)
      label = type_label(type)
      { name: tool_name(action, type), type: type.to_s, action: action.to_sym }.merge(copy_fields(action, label, type))
    end

    def copy_fields(action, label, type)
      {
        title: Copy.title(action, label),
        description: Copy.description(action, label, list_tool: tool_name(:list_access, type)),
        input: { "id" => { description: format(Copy::ID_DESCRIPTION, label: label) } },
        output: Copy.output(action)
      }
    end

    def accessible_types
      return [] unless api_available?

      api_type_names.select { |type| accessible_type?(type) }.sort
    end

    def register_type!(type)
      return if ::RecordingStudioMcp.configuration.type(type)

      ::RecordingStudioMcp.register_type(type: type, description: Copy.type_description(type_label(type)))
    end

    def accessible_type?(type)
      load_type(type)
      RecordingStudio.configuration.capability_enabled?(:accessible, for_type: type)
    end

    def action_enabled?(type, action)
      return false unless api_available?

      names = RecordingStudioApi.capability_actions_for(type, api: :public).map { |registered| registered.name.to_sym }
      names.include?(action.to_sym)
    end

    def type_label(type)
      label = RecordingStudio.recordable_type_label(type).presence
      return label if label
      return type.to_s.demodulize.underscore.humanize unless mcp_available?

      ::RecordingStudioMcp::ToolName.type_public_token(type).underscore.humanize
    end

    def api_type_names
      RecordingStudioApi.configuration.fetch_api(:public).recordable_registry.to_h.keys.map(&:to_s)
    end

    def api_available?
      defined?(::RecordingStudioApi) && ::RecordingStudioApi.respond_to?(:configuration)
    end

    def load_type(type)
      type.to_s.safe_constantize
    end
  end
end
