# frozen_string_literal: true

module RecordingStudioAccessible
  class ApplicationController < (defined?(::ApplicationController) ? ::ApplicationController : ActionController::Base)
    helper RecordingStudioAccessible::ApplicationHelper

    class_attribute :builtin_accessible_layout, instance_accessor: false, default: :host
    class_attribute :inherit_host_layout_conditions, instance_accessor: false, default: true

    layout :recording_studio_accessible_layout

    private

    def recording_studio_accessible_layout
      recording_studio_accessible_layout_or(self.class.builtin_accessible_layout)
    end

    def recording_studio_accessible_layout_or(default)
      return false if default == false

      configured = RecordingStudioAccessible.configuration.layout
      return configured.call(controller: self) if configured.respond_to?(:call)
      return configured if configured.present?

      default == :host ? nil : default
    end

    def _conditional_layout?
      return true unless self.class.inherit_host_layout_conditions
      return true unless defined?(::ApplicationController)

      host_layout_includes_action?
    end

    def host_layout_includes_action?
      conditions = ::ApplicationController._layout_conditions
      return true if conditions.blank?

      only = Array(conditions[:only]).map(&:to_s)
      return only.include?(action_name) if only.any?

      Array(conditions[:except]).map(&:to_s).exclude?(action_name)
    end
  end
end
