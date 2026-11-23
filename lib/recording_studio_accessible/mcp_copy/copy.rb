# frozen_string_literal: true

module RecordingStudioAccessible
  module McpCopy
    # Human copy for per-type access tools. No View, Edit, or Admin names.
    module Copy
      ID_DESCRIPTION = "%<label>s id."
      LIST = [
        "Lists the people who can use this %<name>s, including pending email invitations, so you can see them first.",
        "The %<name>s must already exist. Direct grants must be enabled on it.",
        "This call does not change a grant or an invitation.",
        "Inherited grants are changed on the source recording. A missing %<name>s is rejected. Returns grants."
      ].freeze
      GRANT = [
        "Writes a direct grant so one person can use this %<name>s.",
        "The %<name>s must already exist, and direct grants must be enabled.",
        "Pass actor_id from %<list_tool>s or the host's people lookup, or pass email to invite. Do not pass both.",
        "If that email already belongs to an account, the grant is written now.",
        "Otherwise an invitation is stored and sent.",
        "A second call for the same person revises the existing direct grant. It does not change an inherited grant.",
        "A name this %<name>s does not accept is rejected. Returns the grant, or the pending invitation."
      ].freeze
      UPDATE = [
        "Changes the stored name on a direct grant.",
        "The %<name>s must already exist, and direct grants must be enabled.",
        "Pass actor_id from %<list_tool>s and the new role.",
        "It does not change an inherited grant or a pending invitation.",
        "Changing the last person who can manage grants on this %<name>s is rejected.",
        "If the grant already has that name, the call succeeds and nothing changes. Returns the updated grant."
      ].freeze
      REVOKE = [
        "Removes a direct grant so that person no longer has it on this %<name>s.",
        "The %<name>s must already exist, and direct grants must be enabled.",
        "Pass actor_id from %<list_tool>s.",
        "It does not change an inherited grant, and it does not cancel a pending invitation.",
        "Removing the last person who can manage grants on this %<name>s is rejected.",
        "Returns revoked true and the person who was removed."
      ].freeze

      module_function

      def title(action, label)
        {
          "list_access" => "List who can use this #{label}",
          "grant_access" => "Grant someone this #{label}",
          "update_access" => "Change a direct grant on this #{label}",
          "revoke_access" => "Remove a direct grant on this #{label}"
        }.fetch(action.to_s)
      end

      def description(action, label, list_tool:)
        descriptions.fetch(action.to_sym).map { |sentence| fill(sentence, label, list_tool) }.join(" ")
      end

      def fill(sentence, label, list_tool)
        sentence.gsub("%<name>s", label.to_s.downcase).gsub("%<list_tool>s", list_tool.to_s)
      end

      def descriptions
        { list_access: LIST, grant_access: GRANT, update_access: UPDATE, revoke_access: REVOKE }
      end

      def output(action)
        {
          "list_access" => "grants on this recording",
          "grant_access" => "the grant or the pending invitation",
          "update_access" => "the updated direct grant",
          "revoke_access" => "the removed grant"
        }.fetch(action.to_s)
      end

      def type_description(label)
        "#{label} records. Call describe before you change who can use one."
      end
    end
  end
end
