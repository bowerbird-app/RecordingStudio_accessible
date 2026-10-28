# frozen_string_literal: true

module RecordingStudioAccessible
  class Configuration
    module Registry
      def register_action(...)
        RecordingStudioAccessible.register_action(...)
      end

      def define_action(...)
        RecordingStudioAccessible.define_action(...)
      end

      def authorized_action?(...)
        RecordingStudioAccessible.authorized_action?(...)
      end

      def registered_actions
        RecordingStudioAccessible.registered_actions
      end

      def defined_actions
        RecordingStudioAccessible.defined_actions
      end

      def define_check(...)
        RecordingStudioAccessible.define_check(...)
      end

      def check(...)
        RecordingStudioAccessible.check(...)
      end

      def defined_checks
        RecordingStudioAccessible.defined_checks
      end

      def register_audience(...)
        RecordingStudioAccessible.register_audience(...)
      end

      def registered_audiences
        RecordingStudioAccessible.registered_audiences
      end
    end
  end
end
