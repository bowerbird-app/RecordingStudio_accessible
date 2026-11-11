# frozen_string_literal: true

module RecordingStudioAccessible
  class GrantContext
    SOURCES = %i[grant role_change invite invite_acceptance access_request bootstrap].freeze

    attr_reader :actor, :actor_type, :actor_id, :recording, :role, :previous_role, :source, :granted_by

    def initialize(actor:, recording:, role:, source:, granted_by: nil, previous_role: nil,
                   actor_type: nil, actor_id: nil)
      @actor = actor
      @actor_type = actor_type
      @actor_id = actor_id
      @recording = recording
      @role = role&.to_s
      @previous_role = previous_role&.to_s.presence
      @source = source.to_sym
      @granted_by = granted_by
      raise ArgumentError, "unknown grant source: #{@source.inspect}" unless SOURCES.include?(@source)

      freeze
    end
  end
end
