# frozen_string_literal: true

module RecordingStudioAccessible
  # Host-owned step before an access request is recorded. Accessible never reads the metadata keys.
  module AccessRequestGate
    class << self
      def for_action(action)
        RecordingStudioAccessible.configuration.access_request_gate_for(action)
      end

      def decide(recording:, actor:, action:, request:, carry:)
        gate = for_action(action)
        case state(gate, recording: recording, actor: actor, request: request)
        when :open then { status: :open }
        when :blocked then blocked(gate, recording: recording, actor: actor, request: request, carry: carry)
        else { status: :closed }
        end
      end

      def blocking?(gate, recording:, actor:, request:)
        state(gate, recording: recording, actor: actor, request: request) != :open
      end

      def continuation_url(gate, recording:, actor:, request:)
        return if gate.nil? || !gate.respond_to?(:continuation_url)

        gate.continuation_url(recording: recording, actor: actor, request: request)
      rescue StandardError => e
        report(e)
        nil
      end

      def metadata_for(gate, recording:, actor:)
        return {} if gate.nil? || !gate.respond_to?(:metadata_for)

        gate.metadata_for(recording: recording, actor: actor) || {}
      rescue StandardError => e
        report(e)
        {}
      end

      def report(error)
        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.error("[RecordingStudioAccessible] access request gate failed: #{error.class}: #{error.message}")
        end
        return unless defined?(Rails.error) && Rails.error.respond_to?(:report)

        Rails.error.report(error, handled: true, source: "recording_studio_accessible")
      rescue StandardError
        nil
      end

      private

      def state(gate, recording:, actor:, request:)
        return :open if gate.nil? || !gate.respond_to?(:satisfied?)
        return :blocked unless gate.satisfied?(recording: recording, actor: actor, request: request)

        :open
      rescue StandardError => e
        report(e)
        :closed
      end

      def blocked(gate, recording:, actor:, request:, carry:)
        location = AccessRequestContinuation.location(
          continuation_url(gate, recording: recording, actor: actor, request: request),
          request: request,
          carry: carry
        )
        return { status: :closed } if location.blank?

        { status: :redirect, location: location }
      end
    end
  end
end
