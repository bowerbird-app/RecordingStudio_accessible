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

    LABEL = "Audience limit"
    # I18n interpolation tokens use %{name}, not %<name>s.
    NAME_DEFAULT = "Audience limit: %{action} — %{audiences}" # rubocop:disable Style/FormatStringToken
    WRITE_ERROR = "Create audience limits through RecordingStudioAccessible.set_audience_constraint!"

    # recording_studio_recordable captures label at class load; keep English here.
    recording_studio_recordable label: LABEL, root: false if respond_to?(:recording_studio_recordable)

    def self.audience_write_error
      RecordingStudioAccessible::Copy.t("recordables.access_constraint.write_error", default: WRITE_ERROR)
    end

    def self.recordable_type_label
      RecordingStudioAccessible::Copy.t("recordables.access_constraint.label", default: LABEL)
    end

    class << self
      alias recording_studio_type_label recordable_type_label
    end

    def recordable_name
      names = Array(allowed_audiences).map(&:to_s).reject(&:blank?)
      suffix = names.any? ? names.join(", ") : "granted"
      RecordingStudioAccessible::Copy.t(
        "recordables.access_constraint.name",
        default: NAME_DEFAULT,
        action: action,
        audiences: suffix
      )
    end

    alias recording_studio_label recordable_name
  end
end
