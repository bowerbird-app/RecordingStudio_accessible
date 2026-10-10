# frozen_string_literal: true

require "active_support/concern"

module RecordingStudioAccessible
  module AudienceRecordingCreationGuard
    DUPLICATE_AUDIENCE_RECORDING_ERROR = "Only one live audience setting is allowed per action under the same parent"
    CONSTRAINT_NOT_ROOT_ERROR = "Audience limits can only be added on a workspace"

    extend ActiveSupport::Concern

    included do
      validate :prevent_unsupported_audience_recording_creation, on: :create
      validate :prevent_duplicate_live_audience_recording, on: :create
      validate :prevent_access_constraint_on_non_root, on: :create
    end

    private

    def prevent_unsupported_audience_recording_creation
      return unless audience_recordable?
      return unless audience_placement_enabled?
      return if RecordingStudioAccessible::AudienceWriteContext.allowed?

      errors.add(:base, audience_recordable_class.audience_write_error)
    end

    def prevent_duplicate_live_audience_recording
      return unless audience_recordable?
      return if parent_recording.blank?

      recordable = audience_recordable_instance
      action = recordable&.action
      return if action.blank?

      duplicate = RecordingStudioAccessible::AudienceQuery.live_duplicate_exists?(
        recordable_type: recordable_type_name,
        parent_recording_id: parent_recording_id,
        action: action,
        except_id: id
      )
      errors.add(:base, DUPLICATE_AUDIENCE_RECORDING_ERROR) if duplicate
    end

    def prevent_access_constraint_on_non_root
      return unless constraint_recordable?
      return if parent_recording.blank?
      return if RecordingStudio.root_recording?(parent_recording)
      return if RecordingStudioAccessible::SharedRootAccess.target?(parent_recording)

      errors.add(:parent_recording, CONSTRAINT_NOT_ROOT_ERROR)
    end

    def audience_placement_enabled?
      return false if parent_recording.blank?

      if constraint_recordable? && RecordingStudioAccessible::SharedRootAccess.target?(parent_recording)
        errors.add(:parent_recording, RecordingStudioAccessible::SharedRootAccess::GRANT_DENIED_MESSAGE)
        return false
      end

      return true if RecordingStudioAccessible::Compatibility.audience_parent_allowed?(
        recording: parent_recording,
        child_type: recordable_type_name
      )

      errors.add(:parent_recording, "does not allow #{recordable_type_name} children")
      false
    end

    def audience_recordable?
      constraint_recordable? || rule_recordable?
    end

    def constraint_recordable?
      recordable_type_name == RecordingStudioAccessible::AudienceQuery::CONSTRAINT_TYPE
    end

    def rule_recordable?
      recordable_type_name == RecordingStudioAccessible::AudienceQuery::RULE_TYPE
    end

    def recordable_type_name
      return "RecordingStudio::AccessConstraint" if recordable_type == "RecordingStudio::AccessConstraint"
      return "RecordingStudio::AccessRule" if recordable_type == "RecordingStudio::AccessRule"
      return "RecordingStudio::AccessConstraint" if recordable.is_a?(::RecordingStudio::AccessConstraint)
      return "RecordingStudio::AccessRule" if recordable.is_a?(::RecordingStudio::AccessRule)

      target = association(:recordable).target
      return "RecordingStudio::AccessConstraint" if target.is_a?(::RecordingStudio::AccessConstraint)
      return "RecordingStudio::AccessRule" if target.is_a?(::RecordingStudio::AccessRule)

      recordable_type
    end

    def audience_recordable_instance
      return recordable if audience_recordable_object?(recordable)

      association(:recordable).target
    end

    def audience_recordable_class
      if constraint_recordable?
        ::RecordingStudio::AccessConstraint
      else
        ::RecordingStudio::AccessRule
      end
    end

    def audience_recordable_object?(value)
      return false unless defined?(::RecordingStudio::AccessConstraint)
      return true if value.is_a?(::RecordingStudio::AccessConstraint)
      return true if defined?(::RecordingStudio::AccessRule) && value.is_a?(::RecordingStudio::AccessRule)

      false
    end
  end
end
