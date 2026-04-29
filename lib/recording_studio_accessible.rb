# frozen_string_literal: true

require "recording_studio"
require "action_mailer"
require "recording_studio_accessible/version"
require "recording_studio_accessible/hooks"
require "recording_studio_accessible/allows_accessible_children"
require "recording_studio_accessible/access_management_policy"
require "recording_studio_accessible/actor_type"
require "recording_studio_accessible/authorization_class_methods"
require "recording_studio_accessible/configuration"
require "recording_studio_accessible/compatibility"
require "recording_studio_accessible/authorization"
require "recording_studio_accessible/authorization_service"
require "recording_studio_accessible/direct_access_query"
require "recording_studio_accessible/services/base_service"
require "recording_studio_accessible/services/access_record_lifecycle"
require "recording_studio_accessible/services/create_recording_access_boundary"
require "recording_studio_accessible/services/grant_recording_access"
require "recording_studio_accessible/services/remove_recording_access_boundary"
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

    def role_for(actor:, recording:)
      Authorization.role_for(actor: actor, recording: recording)
    end

    def authorized?(actor:, recording:, role:)
      Authorization.allowed?(actor: actor, recording: recording, role: role)
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
