# frozen_string_literal: true

module RecordingStudio
  # Internal recordable for the selected audience of one named action on one recording.
  #
  # Application code should not create AccessRule records directly. Use:
  #
  #   RecordingStudioAccessible.set_audience!(...)
  class AccessRule < ::ApplicationRecord
    self.table_name = "recording_studio_access_rules"
    include RecordingStudio::Recordable
    include RecordingStudioAccessible::AudienceCreationGuard

    recording_studio_recordable label: "Audience", root: false if respond_to?(:recording_studio_recordable)

    def self.audience_write_error
      "Create audiences through RecordingStudioAccessible.set_audience!"
    end

    def self.recordable_type_label
      "Audience"
    end

    class << self
      alias recording_studio_type_label recordable_type_label
    end

    def recordable_name
      "Audience: #{action} — #{audience}"
    end

    alias recording_studio_label recordable_name
  end
end
