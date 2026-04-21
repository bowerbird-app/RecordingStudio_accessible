# frozen_string_literal: true

module RecordingStudioAccessible
  module Compatibility
    EXTRACTED_FILES = {
      "RecordingStudio::Access" => "recording_studio_accessible/extracted/recording_studio/access",
      "RecordingStudio::AccessBoundary" => "recording_studio_accessible/extracted/recording_studio/access_boundary",
      "RecordingStudio::Services::AccessCheck" => "recording_studio_accessible/extracted/recording_studio/services/access_check",
      "RecordingStudio::Services::AccessCheckClassMethods" => "recording_studio_accessible/extracted/recording_studio/services/access_check_class_methods"
    }.freeze
    RECORDABLE_TYPES = ["RecordingStudio::Access", "RecordingStudio::AccessBoundary"].freeze

    class << self
      def missing_constant_paths
        missing = EXTRACTED_FILES.keys.reject { |name| constant_defined_path?(name) }
        missing.sort_by { |name| load_priority.fetch(name, 99) }.map { |name| EXTRACTED_FILES.fetch(name) }
      end

      def core_access_present?
        RECORDABLE_TYPES.all? { |path| constant_defined_path?(path) } && constant_defined_path?("RecordingStudio::Services::AccessCheck")
      end

      def addon_provides_access?
        missing_constant_paths.any?
      end

      def integration_mode
        addon_provides_access? ? :addon : :core
      end

      def load_missing_constants!(app = nil)
        ensure_application_record_loaded!(app)

        missing_constant_paths.each do |path|
          require path
        end
      end

      def ensure_recordable_types_registered!
        return unless defined?(::RecordingStudio)

        RECORDABLE_TYPES.each do |type_name|
          RecordingStudio.register_recordable_type(type_name) if constant_defined_path?(type_name)
        end
      end

      def warn_if_core_access_present!
        return unless core_access_present?
        return unless RecordingStudioAccessible.configuration.warn_on_core_conflict
        return if defined?(Rails) && Rails.env.test?
        return if @warned_core_access

        message = "[RecordingStudioAccessible] RecordingStudio already provides access models/services. Running in compatibility mode and skipping addon-owned constants and migrations."

        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.info(message)
        else
          warn(message)
        end

        @warned_core_access = true
      end

      private

      def load_priority
        {
          "RecordingStudio::Access" => 1,
          "RecordingStudio::AccessBoundary" => 2,
          "RecordingStudio::Services::AccessCheckClassMethods" => 3,
          "RecordingStudio::Services::AccessCheck" => 4
        }
      end

      def constant_defined_path?(path)
        path.split("::").reject(&:empty?).inject(Object) do |scope, const_name|
          return false unless scope.const_defined?(const_name, false)

          scope.const_get(const_name, false)
        end
        true
      rescue NameError
        false
      end

      def ensure_application_record_loaded!(app)
        return if defined?(::ApplicationRecord)
        return unless app.respond_to?(:paths)

        app.paths["app/models"].existent.each do |models_path|
          application_record_path = File.join(models_path, "application_record.rb")
          require application_record_path if File.file?(application_record_path)
        end
      end
    end
  end
end
