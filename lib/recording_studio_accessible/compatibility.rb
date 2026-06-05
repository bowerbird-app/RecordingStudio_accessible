# frozen_string_literal: true

module RecordingStudioAccessible
  # rubocop:disable Metrics/ModuleLength
  module Compatibility
    EXTRACTED_FILES = {
      "RecordingStudio::Access" => "recording_studio_accessible/extracted/recording_studio/access"
    }.freeze
    RECORDABLE_TYPES = ["RecordingStudio::Access"].freeze
    ACCESS_RECORDABLE_TYPE = "RecordingStudio::Access"
    ACCESS_CAPABILITY = :accessible
    ACCESS_CAPABILITY_SOURCE = "recording_studio_accessible"

    class << self # rubocop:disable Metrics/ClassLength
      def missing_constant_paths
        missing = EXTRACTED_FILES.keys.reject { |name| constant_defined_path?(name) }
        missing.sort_by { |name| load_priority.fetch(name, 99) }.map { |name| EXTRACTED_FILES.fetch(name) }
      end

      def core_access_present?
        !addon_loaded_access? && RECORDABLE_TYPES.all? { |path| constant_defined_path?(path) }
      end

      def addon_provides_access?
        addon_loaded_access? || missing_constant_paths.any?
      end

      def integration_mode
        addon_provides_access? ? :addon : :core
      end

      def load_missing_constants!(app = nil)
        ensure_application_record_loaded!(app)

        missing_constant_paths.each do |path|
          require path
          @addon_loaded_access = true if path == EXTRACTED_FILES.fetch(ACCESS_RECORDABLE_TYPE)
        end

        ensure_creation_guards!
      end

      def addon_loaded_access?
        @addon_loaded_access == true
      end

      def ensure_recordable_types_registered!
        return unless defined?(::RecordingStudio)

        RECORDABLE_TYPES.each do |type_name|
          RecordingStudio.register_recordable_type(type_name) if constant_defined_path?(type_name)
        end
        ensure_access_recordable_declaration!
      end

      def register_access_capability!
        return unless defined?(::RecordingStudio)
        return if compatible_access_capability_registered?

        RecordingStudio.register_capability(
          ACCESS_CAPABILITY,
          source: ACCESS_CAPABILITY_SOURCE,
          child_recordables: [ACCESS_RECORDABLE_TYPE]
        )
      end

      def ensure_creation_guards!
        include_guard("RecordingStudio::Access", RecordingStudioAccessible::AccessCreationGuard)
        include_guard("RecordingStudio::Recording", RecordingStudioAccessible::AccessRecordingCreationGuard)
      end

      def ensure_access_recordable_declaration!
        return unless defined?(::RecordingStudio)

        access_class = constant_for_path(ACCESS_RECORDABLE_TYPE)
        return unless access_class.respond_to?(:recording_studio_recordable)

        access_class.recording_studio_recordable(
          label: "Access",
          root: false
        )
      end

      def warn_if_core_access_present!
        return unless core_access_present?
        return unless RecordingStudioAccessible.configuration.warn_on_core_conflict
        return if defined?(Rails) && Rails.env.test?
        return if @warned_core_access

        message = "[RecordingStudioAccessible] RecordingStudio already provides access models. Running in compatibility mode and skipping addon-owned constants and migrations."

        if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          Rails.logger.info(message)
        else
          warn(message)
        end

        @warned_core_access = true
      end

      private

      def compatible_access_capability_registered?
        registration = RecordingStudio.registered_capabilities[ACCESS_CAPABILITY]
        return false unless registration
        return false if registration[:source].blank? || registration[:source] == ACCESS_CAPABILITY_SOURCE

        Array(registration[:child_recordables]).include?(ACCESS_RECORDABLE_TYPE)
      end

      def load_priority
        {
          "RecordingStudio::Access" => 1
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

      def include_guard(class_name, guard)
        model_class = constant_for_path(class_name)
        return unless model_class

        return if model_class.included_modules.include?(guard)

        model_class.include guard
      end

      def constant_for_path(path)
        scope = Object

        path.split("::").reject(&:empty?).each do |const_name|
          return nil unless scope.const_defined?(const_name, false)

          scope = scope.const_get(const_name, false)
        end

        scope
      rescue NameError
        nil
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end
