# frozen_string_literal: true

module RecordingStudioAccessible
  module RegistryClassMethods
    def action_registry
      @action_registry ||= ActionRegistry.new
    end

    def check_registry
      @check_registry ||= CheckRegistry.new
    end

    def audience_registry
      @audience_registry ||= AudienceRegistry.new
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
      if AudienceResolver.configured?(action)
        return AudienceAuthorization.authorized?(
          actor: actor,
          action: action,
          recording: recording,
          context: context
        )
      end

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

    def register_audience(name, label_key: nil, &)
      audience_registry.register(name, label_key: label_key, &)
    end

    def registered_audiences
      audience_registry.registrations
    end

    def registered_audience?(name)
      audience_registry.registered?(name)
    end

    def audience_registration_for(name)
      audience_registry.registration_for(name)
    end

    def granted_roles_for(action)
      AudienceResolver.granted_roles_for(action)
    end

    def effective_audience(recording:, action:)
      AudienceResolver.effective_audience(recording: recording, action: action)
    end

    def audience_options_for(recording:, action:)
      AudienceResolver.allowed_audiences_for(recording: recording, action: action).map do |audience|
        { audience: audience, label: audience_label_for(audience) }
      end
    end

    def set_audience!(recording:, action:, audience:, actor:)
      result = Services::SetAudience.call(
        recording: recording,
        action: action,
        audience: audience,
        actor: actor
      )
      raise result.error if result.failure?

      result.value
    end

    def set_audience_constraint!(root:, action:, allowed_audiences:, actor:)
      result = Services::SetAudienceConstraint.call(
        root: root,
        action: action,
        allowed_audiences: allowed_audiences,
        actor: actor
      )
      raise result.error if result.failure?

      result.value
    end

    def install_action_audience_policy!(action)
      return unless AudienceResolver.configured?(action)

      warn_if_replacing_defined_action!(action)
      register_action(
        action,
        source: "recording_studio_accessible",
        recording_required: true
      )
      define_action(action) do |actor:, recording:, context: {}, **|
        AudienceAuthorization.authorized?(
          actor: actor,
          action: action,
          recording: recording,
          context: context
        )
      end
    end

    def warn_if_replacing_defined_action!(action)
      return unless action_defined?(action)

      registration = action_registration_for(action)
      return if registration && registration[:source] == "recording_studio_accessible"

      message = "[RecordingStudioAccessible] action #{action.inspect} already has a define_action policy. " \
                "config.action_audiences takes over that action; the host policy will not run."
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.warn(message)
      else
        warn(message)
      end
    end

    def install_action_audience_policies!
      configuration.action_audiences.each_key do |action|
        install_action_audience_policy!(action)
      end
    end

    def audience_label_for(audience)
      metadata = audience_registration_for(audience)
      label_key = metadata&.[](:label_key)
      return audience.to_s.humanize if label_key.blank?

      I18n.t(label_key, default: audience.to_s.humanize)
    rescue StandardError
      audience.to_s.humanize
    end
  end
end
