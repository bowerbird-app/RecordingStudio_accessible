# frozen_string_literal: true

module RecordingStudioAccessible
  module BeforeAccessGrant
    module_function

    def call!(context)
      return if context.source == :bootstrap

      hook = RecordingStudioAccessible.configuration.before_access_grant
      return unless hook.respond_to?(:call)

      hook.call(context)
    end

    def context_for(actor:, recording:, role:, source:, granted_by: nil, previous_role: nil)
      GrantContext.new(
        actor: actor,
        actor_type: actor_type_for(actor),
        actor_id: actor.respond_to?(:id) ? actor.id : nil,
        recording: recording,
        role: role,
        previous_role: previous_role,
        source: source,
        granted_by: granted_by
      )
    end

    def actor_type_for(actor)
      return if actor.nil?

      ActorType.for(actor)
    end
  end
end
