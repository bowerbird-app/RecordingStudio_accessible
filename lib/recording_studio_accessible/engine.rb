# frozen_string_literal: true

module RecordingStudioAccessible
  class Engine < ::Rails::Engine
    isolate_namespace RecordingStudioAccessible

    initializer "recording_studio_accessible.load_config" do |app|
      if app.respond_to?(:config_for)
        begin
          yaml = app.config_for(:recording_studio_accessible)
          RecordingStudioAccessible.configuration.merge!(yaml) if yaml.respond_to?(:each)
        rescue StandardError
          nil
        end
      end

      if app.config.respond_to?(:x) && app.config.x.respond_to?(:recording_studio_accessible)
        xcfg = app.config.x.recording_studio_accessible
        hash = xcfg.respond_to?(:to_h) ? xcfg.to_h : {}
        RecordingStudioAccessible.configuration.merge!(hash) if hash.respond_to?(:each)
      end

      RecordingStudioAccessible::Hooks.run(:on_configuration, RecordingStudioAccessible.configuration)
    end

    initializer "recording_studio_accessible.before_initialize", before: "recording_studio_accessible.load_config" do
      RecordingStudioAccessible::Hooks.run(:before_initialize, self)
    end

    initializer "recording_studio_accessible.register_access_types", after: "recording_studio_accessible.load_config" do
      RecordingStudioAccessible::Compatibility.warn_if_core_access_present!
      RecordingStudioAccessible::Compatibility.ensure_recordable_types_registered!
    end

    initializer "recording_studio_accessible.after_initialize", after: "recording_studio_accessible.register_access_types" do
      RecordingStudioAccessible::Hooks.run(:after_initialize, self)
    end
  end
end
