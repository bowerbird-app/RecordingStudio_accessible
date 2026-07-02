# frozen_string_literal: true

module RecordingStudioAccessible
  class CheckDefinition
    attr_reader :name, :predicate

    def initialize(name:, predicate:)
      @name = name
      @predicate = predicate
    end

    def call(actor:, recording:, context:, controller:)
      arguments = {
        actor: actor,
        recording: recording,
        context: context,
        controller: controller
      }

      predicate.call(**filtered_keyword_arguments(predicate, arguments))
    end

    private

    def filtered_keyword_arguments(callable, arguments)
      parameters = callable.parameters
      return arguments if parameters.any? { |type, _name| type == :keyrest }

      supported_keys = parameters.filter_map do |type, name|
        name if %i[key keyreq].include?(type)
      end

      arguments.slice(*supported_keys)
    end
  end

  class CheckRegistry
    def initialize
      @mutex = Mutex.new
      @definitions = {}
    end

    def define(name, &block)
      normalized_name = normalize_name!(name)
      raise ArgumentError, "check block is required" unless block

      definition = CheckDefinition.new(name: normalized_name, predicate: block).freeze

      @mutex.synchronize do
        @definitions[normalized_name] = definition
      end

      definition
    end

    def check(name, actor:, recording: nil, context: {}, controller: nil)
      return false unless valid_name?(name)

      normalized_context = normalize_context(context)
      return false unless normalized_context.is_a?(Hash)

      definition = definition_for(name)
      return false unless definition

      !!definition.call(
        actor: actor,
        recording: recording,
        context: normalized_context,
        controller: controller
      )
    rescue StandardError
      false
    end

    def definitions
      @mutex.synchronize { @definitions.keys.sort_by(&:to_s) }
    end

    def defined?(name)
      return false unless valid_name?(name)

      @mutex.synchronize { @definitions.key?(name) }
    end

    def checks
      @mutex.synchronize { @definitions.dup.freeze }
    end

    def clear!
      @mutex.synchronize { @definitions.clear }
    end

    private

    def normalize_name!(name)
      raise ArgumentError, "check name must be a non-blank symbol" unless valid_name?(name)

      name
    end

    def valid_name?(name)
      name.is_a?(Symbol) && !name.to_s.strip.empty?
    end

    def normalize_context(context)
      context.nil? ? {} : context
    end

    def definition_for(name)
      @mutex.synchronize { @definitions[name] }
    end
  end
end
