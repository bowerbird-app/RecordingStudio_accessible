# frozen_string_literal: true

require "recording_studio"
require "action_mailer"
require "recording_studio_accessible/version"
require "recording_studio_accessible/hooks"
require "recording_studio_accessible/compatibility"
RecordingStudioAccessible::Compatibility.register_access_capability!
require "recording_studio_accessible/access_creation_context"
require "recording_studio_accessible/access_creation_guard"
require "recording_studio_accessible/access_recording_creation_guard"
require "recording_studio_accessible/access_management_policy"
require "recording_studio_accessible/action_registry"
require "recording_studio_accessible/actor_type"
require "recording_studio_accessible/check_registry"
require "recording_studio_accessible/navigation_url_safety"
require "recording_studio_accessible/authorization_class_methods"
require "recording_studio_accessible/configuration"
require "recording_studio_accessible/authorization"
require "recording_studio_accessible/direct_access_query"
require "recording_studio_accessible/services/base_service"
require "recording_studio_accessible/authorization_service"
require "recording_studio_accessible/services/access_record_lifecycle"
require "recording_studio_accessible/services/grant_recording_access"
require "recording_studio_accessible/services/update_recording_access"
require "recording_studio_accessible/services/revoke_recording_access"
require_relative "../app/mailers/recording_studio_accessible/access_granted_mailer"

require "recording_studio_accessible/engine"

module RecordingStudioAccessible
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end

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

    def define_action(action, &block)
      action_registry.define(action, &block)
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

    def define_check(name, &block)
      check_registry.define(name, &block)
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

    def role_for(actor:, recording:)
      Authorization.role_for(actor: actor, recording: recording)
    end

    def authorized?(actor:, recording:, role:)
      Authorization.allowed?(actor: actor, recording: recording, role: role)
    end

    def role_through(actor:, through:, recording:, controller: nil)
      Authorization.role_through(actor: actor, through: through, recording: recording, controller: controller)
    end

    def authorized_through?(actor:, through:, recording:, role:, controller: nil)
      Authorization.allowed_through?(
        actor: actor,
        through: through,
        recording: recording,
        role: role,
        controller: controller
      )
    end

    def grant_access(recording:, actor:, role:, manager_actor: nil)
      Services::GrantRecordingAccess.call(
        recording: recording,
        actor: actor,
        role: role,
        manager_actor: manager_actor
      )
    end

    def root_recordings_for(actor:, minimum_role: nil)
      Authorization.root_recordings_for(actor: actor, minimum_role: minimum_role)
    end

    def root_recording_ids_for(actor:, minimum_role: nil)
      Authorization.root_recording_ids_for(actor: actor, minimum_role: minimum_role)
    end

    def access_recordings_for(recording)
      Authorization.access_recordings_for(recording)
    end

    def access_recordings_for_actor(recording:, actor:)
      Authorization.access_recordings_for_actor(recording: recording, actor: actor)
    end
  end
end
