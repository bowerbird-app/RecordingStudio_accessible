# frozen_string_literal: true

module RecordingStudioAccessible
  module Compatibility
    ACCESS_CONSTANTS = [
      "RecordingStudio::Access",
      "RecordingStudio::AccessBoundary",
      "RecordingStudio::Services::AccessCheck"
    ].freeze
    RECORDABLE_TYPES = ["RecordingStudio::Access", "RecordingStudio::AccessBoundary"].freeze

    class << self
      def core_access_present?
        ACCESS_CONSTANTS.all? { |path| constant_defined_path?(path) }
      end

      def addon_provides_access?
        !core_access_present?
      end

      def integration_mode
        addon_provides_access? ? :addon : :core
      end

      def ensure_recordable_types_registered!
        return unless defined?(::RecordingStudio)

        RECORDABLE_TYPES.each do |type_name|
          RecordingStudio.register_recordable_type(type_name)
        end
      end

      def warn_if_core_access_present!
        return unless core_access_present?
        return unless RecordingStudioAccessible.configuration.warn_on_core_conflict
        return if defined?(Rails) && Rails.env.test?
        return if @warned_core_access

        message = "[RecordingStudioAccessible] RecordingStudio already provides access models/services. " \
                  "Running in compatibility mode and skipping addon-owned access constants and migrations."

        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.info(message)
        else
          warn(message)
        end

        @warned_core_access = true
      end

      private

      def constant_defined_path?(path)
        path.split("::").reject(&:empty?).inject(Object) do |scope, const_name|
          return false unless scope.const_defined?(const_name, false)

          scope.const_get(const_name, false)
        end
        true
      rescue NameError
        false
      end
    end
  end
end
