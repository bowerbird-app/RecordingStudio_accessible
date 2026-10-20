# frozen_string_literal: true

module RecordingStudioAccessible
  class ApplicationController < (defined?(::ApplicationController) ? ::ApplicationController : ActionController::Base)
    helper RecordingStudioAccessible::ApplicationHelper

    class_attribute :builtin_accessible_layout, instance_accessor: false, default: :host

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

      default == :host ? inherited_host_layout : default
    end

    def inherited_host_layout
      return unless defined?(::ApplicationController)

      case (specification = ::ApplicationController._layout)
      when Symbol
        send(specification)
      when Proc
        specification.arity.zero? ? specification.call : specification.call(self)
      when String
        specification
      end
    end
  end
end
