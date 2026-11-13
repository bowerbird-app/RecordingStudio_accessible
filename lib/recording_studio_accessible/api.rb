# frozen_string_literal: true

require "recording_studio_accessible/api/support"
require "recording_studio_accessible/api/actions"
require "recording_studio_accessible/api/openapi_copy"
require "recording_studio_accessible/api/openapi_schemas"
require "recording_studio_accessible/api/action_definitions"
require "recording_studio_accessible/api/openapi_overrides"
require "recording_studio_accessible/api/registration"

module RecordingStudioAccessible
  module Api
    ACTION_VERSION = "1.0.0"
    INTERNAL_ROUTE_PARAMETER_KEYS = %i[api_key api_version member_action]
                                    .push("api_key", "api_version", "member_action").freeze
    IDENTITY_SERIALIZER = ->(payload) { payload }
    ACTION_NAMES = %i[list_access grant_access update_access revoke_access].freeze

    class << self
      def override_openapi(type:, action:, title:, description:)
        OpenapiOverrides.store(type: type, action: action, title: title, description: description)
      end

      def openapi_for(action, type: nil)
        OpenapiOverrides.document(action, type: type)
      end
    end

    extend Registration
  end
end
