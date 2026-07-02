# frozen_string_literal: true

require "thread"

module RecordingStudioAccessible
  class ActionDefinition
    attr_reader :name, :policy

    def initialize(name:, policy:)
      @name = name
      @policy = policy
    end

    def call(actor:, action:, recording:, context:, controller:)
      policy.call(
        actor: actor,
        action: action,
        recording: recording,
        context: context,
        controller: controller
      )
    end
  end

  class ActionRegistry
    def initialize
      @mutex = Mutex.new
      @registrations = {}
      @definitions = {}
    end

    def register(name, label: nil, description: nil, source: nil, recording_required: false)
      normalized_name = normalize_name!(name)
      metadata = {
        name: normalized_name,
        label: label,
        description: description,
        source: source,
        recording_required: !!recording_required
      }

      @mutex.synchronize do
        @registrations[normalized_name] = metadata.freeze
      end

      metadata.dup
    end

    def define(name, &block)
      normalized_name = normalize_name!(name)
      raise ArgumentError, "action policy block is required" unless block

      definition = ActionDefinition.new(name: normalized_name, policy: block)

      @mutex.synchronize do
        @definitions[normalized_name] = definition
      end

      definition
    end

    def authorized?(actor:, action:, recording: nil, context: {}, controller: nil)
      return false unless valid_name?(action)

      normalized_context = context.nil? ? {} : context
      return false unless normalized_context.is_a?(Hash)

      normalized_action = action
      registration = registration_for(normalized_action)
      return false if registration && registration[:recording_required] && recording.nil?

      definition = definition_for(normalized_action)
      return false unless definition

      !!definition.call(
        actor: actor,
        action: normalized_action,
        recording: recording,
        context: normalized_context,
        controller: controller
      )
    rescue StandardError
      false
    end

    def registrations
      @mutex.synchronize do
        @registrations.keys.sort_by(&:to_s).to_h do |name|
          [name, @registrations.fetch(name).dup]
        end
      end
    end

    def registered?(name)
      return false unless valid_name?(name)

      @mutex.synchronize { @registrations.key?(name) }
    end

    def registration_for(name)
      return nil unless valid_name?(name)

      @mutex.synchronize do
        metadata = @registrations[name]
        metadata&.dup
      end
    end

    def definitions
      @mutex.synchronize { @definitions.keys.sort_by(&:to_s) }
    end

    def defined?(name)
      return false unless valid_name?(name)

      @mutex.synchronize { @definitions.key?(name) }
    end

    def action_policies
      @mutex.synchronize { @definitions.dup }
    end

    def clear!
      @mutex.synchronize do
        @registrations.clear
        @definitions.clear
      end
    end

    private

    def normalize_name!(name)
      raise ArgumentError, "action name must be a non-blank symbol" unless valid_name?(name)

      name
    end

    def valid_name?(name)
      name.is_a?(Symbol) && !name.to_s.strip.empty?
    end

    def definition_for(name)
      @mutex.synchronize { @definitions[name] }
    end
  end
end
