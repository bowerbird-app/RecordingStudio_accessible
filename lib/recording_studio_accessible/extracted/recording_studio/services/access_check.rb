# frozen_string_literal: true

require "recording_studio_accessible/extracted/recording_studio/access_roles"
require_relative "access_resolver"

module RecordingStudio
  module Services
    class AccessCheck < RecordingStudio::Services::BaseService
      extend AccessCheckClassMethods

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

        resolved = AccessResolver.new(actor: @actor, recording: @recording).resolve_role
        return success(role_satisfies_requirement?(resolved)) if @role

        success(resolved&.to_sym)
      end

      def role_satisfies_requirement?(resolved)
        RecordingStudio::AccessRoles.satisfies?(role: resolved, minimum_role: @role)
      end
    end
  end
end
