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

    LABEL = "Audience"
    # I18n interpolation tokens use %{name}, not %<name>s.
    NAME_DEFAULT = "Audience: %{action} — %{audience}" # rubocop:disable Style/FormatStringToken
    WRITE_ERROR = "Create audiences through RecordingStudioAccessible.set_audience!"

    # recording_studio_recordable captures label at class load; keep English here.
    recording_studio_recordable label: LABEL, root: false if respond_to?(:recording_studio_recordable)

    def self.audience_write_error
      RecordingStudioAccessible::Copy.t("recordables.access_rule.write_error", default: WRITE_ERROR)
    end

    def self.recordable_type_label
      RecordingStudioAccessible::Copy.t("recordables.access_rule.label", default: LABEL)
    end

    class << self
      alias recording_studio_type_label recordable_type_label
    end

    def recordable_name
      RecordingStudioAccessible::Copy.t(
        "recordables.access_rule.name",
        default: NAME_DEFAULT,
        action: action,
        audience: audience
      )
    end

    alias recording_studio_label recordable_name
  end
end
