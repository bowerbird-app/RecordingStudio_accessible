# frozen_string_literal: true

module RecordingStudioAccessible
  module Api
    module OpenapiOverrides
      module_function

      def store(type:, action:, title:, description:)
        type_name = normalized_type!(type)
        name = normalized_action!(action)
        raise ArgumentError, "title is required" if title.nil?
        raise ArgumentError, "description is required" if description.nil?

        entries[type_name] ||= {}
        entries[type_name][name] = { title: title, description: description }.freeze
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
