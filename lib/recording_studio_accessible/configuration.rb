# frozen_string_literal: true

require_relative "hooks"
require_relative "missing_actor_resolution"
require_relative "configuration/call_helpers"
require_relative "configuration/attributes"
require_relative "configuration/avatars"
require_relative "configuration/actors"
require_relative "configuration/authorizers"
require_relative "configuration/access_requests"
require_relative "configuration/registry"
require_relative "configuration/missing_actors"
require_relative "configuration/granted_notifications"
require_relative "configuration/granted_urls"
require_relative "configuration/invitations"
require_relative "configuration/invitation_mail"
require "uri"

module RecordingStudioAccessible
  class Configuration
    include CallHelpers
    include Attributes
    include Avatars
    include Actors
    include Authorizers
    include AccessRequests
    include Registry
    include MissingActors
    include GrantedNotifications
    include GrantedUrls
    include Invitations
    include InvitationMail

    FALLBACK_ACCESS_REQUEST_GATE = :default

    def initialize
      assign_core_defaults
      assign_avatar_defaults
      assign_actor_defaults
      assign_authorizer_defaults
      assign_missing_actor_defaults
      assign_granted_notification_defaults
      assign_invitation_defaults
      assign_access_request_defaults
      install_action_audience_change_hook
    end

    def layout=(value)
      @layout = RecordingStudio::Layout.accept(value)
    end

    def action_audiences=(value)
      @action_audiences ||= ActionAudiences.new
      @action_audiences.replace(value)
    end

    def to_h
      {
        warn_on_core_conflict: warn_on_core_conflict,
        hooks_registered: hooks.instance_variable_get(:@registry).transform_values(&:size)
      }
    end

    def merge!(hash)
      return unless hash.respond_to?(:each)

      hash.each { |key, value| merge_entry!(key, value) }
    end

    private

    def assign_core_defaults
      @warn_on_core_conflict = true
      @layout = nil
      @hooks = Hooks.new
      @action_audiences = ActionAudiences.new
    end

    def install_action_audience_change_hook
      owner = self
      @action_audiences.on_change = lambda do |action|
        next unless RecordingStudioAccessible.instance_variable_get(:@configuration).equal?(owner)

        RecordingStudioAccessible.install_action_audience_policy!(action)
      end
    end

    def merge_entry!(key, value)
      name = key.to_s
      setter = "#{name}="
      return unless respond_to?(setter)

      apply_merge_value(name, setter, value)
    end

    def apply_merge_value(name, setter, value)
      public_send(setter, cast_boolean(value)) if name == "warn_on_core_conflict"
      public_send(setter, value) if name == "avatar_resolver" && value.respond_to?(:call)
      public_send(setter, value) if name == "action_audiences"
    end
  end
end
