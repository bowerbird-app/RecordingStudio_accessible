# frozen_string_literal: true

require "active_support/concern"

module RecordingStudioAccessible
  module AllowsAccessibleChildren
    extend ActiveSupport::Concern

    VALID_CHILD_TYPES = %i[access].freeze

    included do
      class_attribute :recording_studio_accessible_child_types, instance_writer: false, default: [].freeze
    end

    class_methods do
      def recording_studio_accessible_children(*child_types)
        normalized_child_types = child_types.flatten.compact.map { |child_type| normalize_child_type(child_type) }

        self.recording_studio_accessible_child_types = normalized_child_types.uniq.freeze
      end

      def allows_recording_studio_accessible_child?(child_type)
        recording_studio_accessible_child_types.include?(normalize_child_type(child_type))
      end

      private

      def normalize_child_type(child_type)
        normalized_child_type = child_type.to_sym
        return normalized_child_type if VALID_CHILD_TYPES.include?(normalized_child_type)

        raise ArgumentError, "Unknown RecordingStudioAccessible child type: #{child_type.inspect}"
      end
    end

    def allows_recording_studio_accessible_child?(child_type)
      self.class.allows_recording_studio_accessible_child?(child_type)
    end
  end

  module PlacementPolicy
    class << self
      def allowed_child_on_recording?(recording:, child_type:)
        recordable = recording&.recordable
        return false unless recordable.respond_to?(:allows_recording_studio_accessible_child?)

        recordable.allows_recording_studio_accessible_child?(child_type)
      end
    end
  end
end
