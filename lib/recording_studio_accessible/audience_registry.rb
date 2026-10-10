# frozen_string_literal: true

module RecordingStudioAccessible
  class AudienceDefinition
    attr_reader :name, :label_key, :predicate

    def initialize(name:, label_key:, predicate:)
      @name = name
      @label_key = immutable_metadata_value(label_key)
      @predicate = predicate
    end

    def call(actor:, recording:, context:)
      arguments = {
        actor: actor,
        recording: recording,
        context: context
      }

      predicate.call(**filtered_keyword_arguments(predicate, arguments))
    end

    def metadata
      { name: name, label_key: label_key }
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

    def immutable_metadata_value(value)
      return value unless value.respond_to?(:dup)

      value.dup.freeze
    rescue TypeError
      value
    end
  end

  class AudienceRegistry
    BUILT_IN_LABEL_PREFIX = "recording_studio.accessible.audiences"
    DENIED = :denied
    PUBLIC = :public
    SIGNED_IN = :signed_in
    GRANTED = :granted
    BUILT_IN_NAMES = [PUBLIC, SIGNED_IN, GRANTED].freeze

    def initialize
      @mutex = Mutex.new
      @definitions = {}
      register_built_ins!
    end

    def register(name, label_key: nil, &block)
      normalized_name = normalize_name!(name)
      raise ArgumentError, "audience predicate block is required" unless block

      definition = AudienceDefinition.new(
        name: normalized_name,
        label_key: label_key.presence || default_label_key(normalized_name),
        predicate: block
      ).freeze

      @mutex.synchronize do
        @definitions[normalized_name] = definition
      end

      definition.metadata.merge(name: normalized_name)
    end

    def registered?(name)
      return false unless valid_name?(name)

      @mutex.synchronize { @definitions.key?(name) }
    end

    def registration_for(name)
      return nil unless valid_name?(name)

      @mutex.synchronize do
        definition = @definitions[name]
        definition&.metadata&.dup
      end
    end

    def registrations
      @mutex.synchronize do
        @definitions.keys.sort_by(&:to_s).to_h do |name|
          [name, @definitions.fetch(name).metadata.dup]
        end
      end
    end

    def names
      @mutex.synchronize { @definitions.keys.sort_by(&:to_s) }
    end

    def evaluate(name, actor:, recording:, context: {})
      return false unless valid_name?(name)

      normalized_context = context.nil? ? {} : context
      return false unless normalized_context.is_a?(Hash)

      definition = definition_for(name)
      return false unless definition

      !!definition.call(actor: actor, recording: recording, context: normalized_context)
    rescue StandardError
      false
    end

    def clear!
      @mutex.synchronize { @definitions.clear }
      register_built_ins!
    end

    def built_in?(name)
      BUILT_IN_NAMES.include?(name)
    end

    private

    def register_built_ins!
      register(PUBLIC, label_key: "#{BUILT_IN_LABEL_PREFIX}.public") { true }
      register(SIGNED_IN, label_key: "#{BUILT_IN_LABEL_PREFIX}.signed_in") { |actor:| actor.present? }
      register(GRANTED, label_key: "#{BUILT_IN_LABEL_PREFIX}.granted") do |actor:, recording:, context:|
        action = context.is_a?(Hash) ? context[:action] : nil
        roles = RecordingStudioAccessible.granted_roles_for(action)
        RecordingStudioAccessible.authorized_for_any_role?(actor: actor, recording: recording, roles: roles)
      end
    end

    def default_label_key(name)
      "#{BUILT_IN_LABEL_PREFIX}.#{name}"
    end

    def normalize_name!(name)
      raise ArgumentError, "audience name must be a non-blank symbol" unless valid_name?(name)

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
