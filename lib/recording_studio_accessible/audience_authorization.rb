# frozen_string_literal: true

module RecordingStudioAccessible
  module AudienceAuthorization
    DENIED = AudienceRegistry::DENIED
    GRANTED = AudienceRegistry::GRANTED

    class << self
      def authorized?(actor:, action:, recording:, context: {})
        return false unless recording
        return false unless AudienceResolver.configured?(action)

        effective = AudienceResolver.effective_audience(recording: recording, action: action)
        return false if effective == DENIED

        eval_context = normalized_context(context).merge(action: action)
        return false unless eval_context.is_a?(Hash)
        return true if audience_passes?(effective, actor: actor, recording: recording, context: eval_context)
        return false unless AudienceResolver.granted_override?(action)

        audience_passes?(GRANTED, actor: actor, recording: recording, context: eval_context)
      rescue StandardError
        false
      end

      def audience_passes?(audience, actor:, recording:, context:)
        return false if audience.nil? || audience == DENIED
        return false unless RecordingStudioAccessible.registered_audience?(audience)

        RecordingStudioAccessible.audience_registry.evaluate(
          audience,
          actor: actor,
          recording: recording,
          context: context
        )
      rescue StandardError
        false
      end

      private

      def normalized_context(context)
        context.nil? ? {} : context
      end
    end
  end
end
