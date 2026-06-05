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
        return unless normalized_child_types.include?(:access)

        RecordingStudio.enable_capability(RecordingStudioAccessible::Compatibility::ACCESS_CAPABILITY, on: self)
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
        return false unless normalize_child_type(child_type) == :access
        return false unless defined?(::RecordingStudio)

        recordable_type = RecordingStudio.recordable_type_name(recordable)
        return false if recordable_type.blank?

        RecordingStudio.capability_enabled?(
          RecordingStudioAccessible::Compatibility::ACCESS_CAPABILITY,
          for: recordable_type
        ) ||
          RecordingStudio.child_recordable_types_for(recordable_type).include?(
            RecordingStudioAccessible::Compatibility::ACCESS_RECORDABLE_TYPE
          )
      end

      private

      def normalize_child_type(child_type)
        child_type.to_sym
      rescue NoMethodError
        nil
      end
    end
  end
end
