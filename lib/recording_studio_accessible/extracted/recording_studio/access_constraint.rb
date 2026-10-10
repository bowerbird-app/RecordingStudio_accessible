# frozen_string_literal: true

module RecordingStudio
  # Internal recordable for a workspace-level audience limit on one named action.
  #
  # Application code should not create AccessConstraint records directly. Use:
  #
  #   RecordingStudioAccessible.set_audience_constraint!(...)
  class AccessConstraint < ::ApplicationRecord
    self.table_name = "recording_studio_access_constraints"
    include RecordingStudio::Recordable
    include RecordingStudioAccessible::AudienceCreationGuard

    recording_studio_recordable label: "Audience limit", root: false if respond_to?(:recording_studio_recordable)

    def self.audience_write_error
      "Create audience limits through RecordingStudioAccessible.set_audience_constraint!"
    end

    def self.recordable_type_label
      "Audience limit"
    end

    class << self
      alias recording_studio_type_label recordable_type_label
    end

    def recordable_name
      names = Array(allowed_audiences).map(&:to_s).reject(&:blank?)
      suffix = names.any? ? names.join(", ") : "granted"
      "Audience limit: #{action} — #{suffix}"
    end

    alias recording_studio_label recordable_name
  end
end
