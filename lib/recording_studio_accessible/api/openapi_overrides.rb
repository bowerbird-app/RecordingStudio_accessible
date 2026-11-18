# frozen_string_literal: true

module RecordingStudioAccessible
  module Api
    module OpenapiOverrides
      OVERRIDE_FIELDS = %i[title description tag_suffix].freeze

      module_function

      def store(type:, action:, **overrides)
        type_name = normalized_type!(type)
        name = normalized_action!(action)

        entries[type_name] ||= {}
        entries[type_name][name] = overlay!(overrides)
      end

      def fetch(type, action)
        return if type.nil?

        entries.dig(type.to_s, action.to_sym)
      end

      def document(action, type: nil)
        base = dup_hash(ACTION_DEFINITIONS.fetch(action.to_sym).fetch(:openapi))
        overlay = fetch(type, action)
        overlay ? base.merge(overlay) : base
      end

      def reset!
        @entries = {}
      end

      def entries
        @entries ||= {}
      end

      def overlay!(overrides)
        fields = overrides.transform_keys(&:to_sym)
        unknown = fields.keys - OVERRIDE_FIELDS
        raise ArgumentError, "Unknown OpenAPI override #{unknown.first.inspect}" if unknown.any?
        raise ArgumentError, "pass title, description, or tag_suffix" if fields.empty?

        fields.each do |key, value|
          raise ArgumentError, "#{key} is required" if value.nil?
        end

        fields.freeze
      end

      def normalized_type!(type)
        type_name = type.to_s
        raise ArgumentError, "type is required" if type_name.blank?

        type_name
      end

      def normalized_action!(action)
        name = action.to_sym
        raise ArgumentError, "Unknown Accessible action #{action.inspect}" unless ACTION_NAMES.include?(name)

        name
      end

      def dup_hash(value)
        value.respond_to?(:deep_dup) ? value.deep_dup : Marshal.load(Marshal.dump(value))
      end
    end
  end
end
