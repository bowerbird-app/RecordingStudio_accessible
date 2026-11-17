# frozen_string_literal: true

require "recording_studio_accessible/extracted/recording_studio/access_roles"
require "recording_studio_accessible/extracted/recording_studio/services/access_resolver"

module RecordingStudioAccessible
  class AuthorizationService < RecordingStudioAccessible::Services::BaseService
    extend AuthorizationClassMethods

    def initialize(actor:, recording:, role: nil, include_trashed: false)
      super()
      @actor = actor
      @recording = recording
      @role = role&.to_s
      @include_trashed = include_trashed
    end

    private

    def perform
      return success(false) if @actor.nil? && @role
      return success(nil) if @actor.nil?

      resolved = RecordingStudio::Services::AccessResolver.new(
        actor: @actor, recording: recording_for_role
      ).resolve_role
      return success(role_satisfies_requirement?(resolved)) if @role

      success(resolved&.to_sym)
    end

    # `include_trashed` keeps a trashed recording on the same grant chain.
    # It does not replace the recording with its parent. Kept-grant lookup
    # still drops a trashed or voided grant, so the role cannot be wider
    # than the role this recording would have while kept.
    def recording_for_role
      return @recording unless @include_trashed

      @recording
    end

    def role_satisfies_requirement?(resolved)
      RecordingStudio::AccessRoles.satisfies?(role: resolved, minimum_role: @role)
    end
  end
end
