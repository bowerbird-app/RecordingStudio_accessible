# frozen_string_literal: true

module RecordingStudioAccessible
  class Configuration
    module AccessRequests
      def access_request_index_recordings_for(actor:, controller:)
        resolver = access_request_index_recordings
        return if resolver.blank?

        resolver.call(**filtered_keyword_arguments(resolver, actor: actor, controller: controller))
      end

      def register_access_request_gate(action_key, gate)
        raise ArgumentError, "action is required" if action_key.blank?
        raise ArgumentError, "gate is required" if gate.nil?

        access_request_gates[action_key.to_sym] = gate
      end

      def access_request_gate_for(action)
        access_request_gates[gate_key(action)] || access_request_gates[FALLBACK_ACCESS_REQUEST_GATE]
      end

      def gate_key(action)
        action.blank? ? FALLBACK_ACCESS_REQUEST_GATE : action.to_sym
      end

      def notify_access_request_submitted(controller:, request_recording:, recording:, actor:, role:)
        resolve_configurable(
          access_request_submitted_notifier,
          controller: controller,
          request_recording: request_recording,
          recording: recording,
          actor: actor,
          role: role
        )
      end

      def notify_access_request_denied(controller:, request_recording:, recording:, actor:, review_note:)
        resolve_configurable(
          access_request_denied_notifier,
          controller: controller,
          request_recording: request_recording,
          recording: recording,
          actor: actor,
          review_note: review_note
        )
      end

      private

      def assign_access_request_defaults
        @access_request_submitted_notifier = method(:default_access_request_submitted_notifier)
        @access_request_denied_notifier = nil
        @access_request_gates = {}
      end

      def default_access_request_submitted_notifier(controller:, request_recording:, recording:, actor:, role:)
        AccessRequestSubmittedNotifier.call(
          controller: controller,
          request_recording: request_recording,
          recording: recording,
          actor: actor,
          role: role
        )
      end
    end
  end
end
