# frozen_string_literal: true

require "recording_studio_accessible/extracted/recording_studio/access_roles"
require "recording_studio_accessible/extracted/recording_studio/services/access_resolver"

module RecordingStudioAccessible
  class AuthorizationService < RecordingStudioAccessible::Services::BaseService
    extend AuthorizationClassMethods

    def initialize(actor:, recording:, role: nil)
      super()
      @actor = actor
      @recording = recording
      @role = role&.to_s
    end

    private

    def perform
      return success(false) if @actor.nil? && @role
      return success(nil) if @actor.nil?

      resolver = RecordingStudio::Services::AccessResolver.new(actor: @actor, recording: @recording)
      return success(resolver.resolve_role&.to_sym) unless @role
      return success(false) if custom_role_closed?

      success(resolver.meets?(@role))
    end

    def custom_role_closed?
      RecordingStudioAccessible::RoleRegistry.custom_name?(@role) &&
        !RecordingStudioAccessible::RoleRegistry.declares?(@recording, @role)
    end
  end
end
