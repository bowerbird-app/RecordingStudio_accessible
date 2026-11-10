# frozen_string_literal: true

require "recording_studio_accessible/api/support"
require "recording_studio_accessible/api/actions"
require "recording_studio_accessible/api/action_definitions"

module RecordingStudioAccessible
  module Api
    ACTION_VERSION = "1.0.0"
    INTERNAL_ROUTE_PARAMETER_KEYS = %i[api_key api_version].push("api_key", "api_version").freeze
    IDENTITY_SERIALIZER = ->(payload) { payload }
    ACTION_NAMES = %i[list_access grant_access update_access revoke_access].freeze

    class << self
      def register_capability_actions!
        return unless recording_studio_api_available?

        if named_api_registration_supported?
          RecordingStudioApi.configuration.each_api do |api_definition|
            register_actions_for(api_definition.name)
          end
        else
          register_actions_for(nil)
        end
      end

      private

      def register_actions_for(api_name)
        ACTION_NAMES.each do |name|
          next if capability_action_registered?(name, api_name)

          options = action_options(name)
          if api_name
            RecordingStudioApi.register_capability_action(name, api: api_name, **options)
          else
            RecordingStudioApi.register_capability_action(name, **options)
          end
        end
      end

      def capability_action_registered?(name, api_name)
        if api_name
          RecordingStudioApi.capability_action(name, api: api_name)
        else
          RecordingStudioApi.capability_action(name)
        end
      end

      def named_api_registration_supported?
        RecordingStudioApi.respond_to?(:configuration) &&
          RecordingStudioApi.configuration.respond_to?(:each_api) &&
          action_api_accepts_api?(:capability_action) &&
          action_api_accepts_api?(:register_capability_action)
      end

      def action_api_accepts_api?(method_name)
        RecordingStudioApi.method(method_name).parameters.any? do |type, name|
          type == :keyrest || (name == :api && %i[key keyreq].include?(type))
        end
      end

      def recording_studio_api_available?
        defined?(RecordingStudioApi) &&
          RecordingStudioApi.respond_to?(:capability_action) &&
          RecordingStudioApi.respond_to?(:register_capability_action)
      end

      def action_options(name)
        definition = ACTION_DEFINITIONS.fetch(name)
        action_metadata.merge(
          handler: definition.fetch(:handler),
          serializer: IDENTITY_SERIALIZER,
          input_contract: input_contract_for(definition.fetch(:fields)),
          openapi: definition.fetch(:openapi)
        )
      end

      def action_metadata
        {
          capability: :accessible,
          version: ACTION_VERSION,
          version_notes: ["Accessible-owned access management action"],
          http_verb: :post,
          scope: :member,
          required_role: :admin
        }
      end

      def input_contract_for(fields)
        definition = { reject_unknown: true, fields: fields }
        return definition unless defined?(RecordingStudioApi::ActionInputContract)

        route_parameter_filtering_contract.new(definition)
      end

      def route_parameter_filtering_contract
        Class.new(RecordingStudioApi::ActionInputContract) do
          define_method(:call) do |raw_params|
            params = raw_params.respond_to?(:to_h) ? raw_params.to_h : raw_params
            if params.respond_to?(:except)
              params = params.except(*RecordingStudioAccessible::Api::INTERNAL_ROUTE_PARAMETER_KEYS)
            end
            super(params)
          end
        end
      end
    end
  end
end
