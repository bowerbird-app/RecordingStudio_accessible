# frozen_string_literal: true

module RecordingStudioAccessible
  module RegistryClassMethods
    def action_registry
      @action_registry ||= ActionRegistry.new
    end

    def check_registry
      @check_registry ||= CheckRegistry.new
    end

    def register_action(action, label: nil, description: nil, source: nil, recording_required: false)
      action_registry.register(
        action,
        label: label,
        description: description,
        source: source,
        recording_required: recording_required
      )
    end

    def registered_actions
      action_registry.registrations
    end

    def registered_action?(action)
      action_registry.registered?(action)
    end

    def action_registration_for(action)
      action_registry.registration_for(action)
    end

    def define_action(action, &)
      action_registry.define(action, &)
    end

    def authorized_action?(actor:, action:, recording: nil, context: {}, controller: nil)
      action_registry.authorized?(
        actor: actor,
        action: action,
        recording: recording,
        context: context,
        controller: controller
      )
    end

    def defined_actions
      action_registry.definitions
    end

    def action_policies
      action_registry.action_policies
    end

    def action_defined?(action)
      action_registry.defined?(action)
    end
    alias action_policy_defined? action_defined?

    def define_check(name, &)
      check_registry.define(name, &)
    end

    def check(name, actor:, recording: nil, context: {}, controller: nil)
      check_registry.check(
        name,
        actor: actor,
        recording: recording,
        context: context,
        controller: controller
      )
    end

    def defined_checks
      check_registry.definitions
    end

    def check_defined?(name)
      check_registry.defined?(name)
    end
  end
end
