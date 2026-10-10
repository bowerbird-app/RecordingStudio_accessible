# frozen_string_literal: true

module RecordingStudioAccessible
  module AudienceResolver
    DENIED = AudienceRegistry::DENIED
    GRANTED = AudienceRegistry::GRANTED

    class << self
      def configured?(action)
        action.is_a?(Symbol) && RecordingStudioAccessible.configuration.action_audiences.configured?(action)
      end

      def config_for(action)
        return unless configured?(action)

        RecordingStudioAccessible.configuration.action_audiences[action]
      end

      def valid_config?(action)
        settings = resolved_settings(action)
        settings && settings[:valid]
      end

      def resolved_settings(action)
        return invalid_settings unless configured?(action)

        entry = config_for(action)
        return invalid_settings if entry.nil?

        allowed = Array(entry[:allowed])
        allowed |= [GRANTED]
        return invalid_settings if allowed.empty?
        return invalid_settings unless allowed.all? { |name| registered_audience?(name) }
        return invalid_settings if entry[:default] && !registered_audience?(entry[:default])

        granted_roles = Array(entry[:granted_roles]).filter_map { |role| role.to_s.strip.presence }
        {
          valid: true,
          allowed: allowed.uniq,
          default: entry[:default],
          granted_roles: granted_roles,
          granted_override: entry[:granted_override] ? true : false,
          manage_role: entry[:manage_role] || :admin,
          denied: granted_roles.empty?
        }
      rescue StandardError
        invalid_settings
      end

      def allowed_audiences_for(recording:, action:)
        settings = resolved_settings(action)
        return [] unless settings[:valid]
        return [] if settings[:denied]

        host_allowed = settings[:allowed]
        constraint = constraint_audiences(recording: recording, action: action)
        allowed = constraint ? (host_allowed & constraint) : host_allowed
        allowed |= [GRANTED]
        allowed.select { |name| registered_audience?(name) }.uniq
      rescue StandardError
        []
      end

      def effective_audience(recording:, action:)
        return DENIED unless recording
        return DENIED unless configured?(action)

        settings = resolved_settings(action)
        return DENIED unless settings[:valid]
        return DENIED if settings[:denied]

        allowed = allowed_audiences_for(recording: recording, action: action)
        return DENIED if allowed.empty?

        stored = stored_audience(recording: recording, action: action)
        if stored
          return stored if allowed.include?(stored)
          return GRANTED if registered_audience?(stored) && allowed.include?(GRANTED)

          return DENIED
        end

        default = settings[:default]
        return default if default && allowed.include?(default)
        return GRANTED if allowed.include?(GRANTED)

        DENIED
      rescue StandardError
        DENIED
      end

      def granted_roles_for(action)
        settings = resolved_settings(action)
        return [] unless settings[:valid]

        settings[:granted_roles]
      rescue StandardError
        []
      end

      def granted_override?(action)
        settings = resolved_settings(action)
        return false unless settings[:valid]

        settings[:granted_override]
      rescue StandardError
        false
      end

      def manage_role_for(action)
        settings = resolved_settings(action)
        return :admin unless settings[:valid]

        settings[:manage_role] || :admin
      rescue StandardError
        :admin
      end

      private

      def invalid_settings
        {
          valid: false,
          allowed: [],
          default: nil,
          granted_roles: [],
          granted_override: false,
          manage_role: :admin,
          denied: true
        }
      end

      def registered_audience?(name)
        RecordingStudioAccessible.registered_audience?(name)
      end

      def stored_audience(recording:, action:)
        rule_recording = AudienceQuery.rule_recording_for(recording: recording, action: action)
        audience = rule_recording&.recordable&.audience
        return if audience.blank?

        audience.to_sym
      rescue StandardError
        nil
      end

      def constraint_audiences(recording:, action:)
        root = RecordingStudio.root_recording_or_self(recording)
        return unless root

        constraint_recording = AudienceQuery.constraint_recording_for(root: root, action: action)
        return unless constraint_recording

        names = Array(constraint_recording.recordable&.allowed_audiences).filter_map do |name|
          normalized = name.to_s.strip
          next if normalized.empty?

          normalized.to_sym
        end
        names |= [GRANTED]
        names.uniq
      rescue StandardError
        nil
      end
    end
  end
end
