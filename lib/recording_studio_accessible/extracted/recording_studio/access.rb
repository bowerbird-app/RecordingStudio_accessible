# frozen_string_literal: true

module RecordingStudio
  # Internal recordable used by RecordingStudioAccessible to represent a direct
  # access grant.
  #
  # Application code should not create Access records directly. Use:
  #
  #   RecordingStudioAccessible.grant_access(...)
  #
  # Direct creation bypasses placement checks, authorization checks, and
  # duplicate-grant deduplication.
  class Access < ::ApplicationRecord
    self.table_name = "recording_studio_accesses"
    include RecordingStudio::Recordable
    include RecordingStudioAccessible::AccessCreationGuard

    LABEL = "Access"
    NAME_DEFAULT = "Access: %{role} — %{actor}"

    # recording_studio_recordable captures label at class load; keep English here.
    recording_studio_recordable label: LABEL, root: false if respond_to?(:recording_studio_recordable)

    belongs_to :actor, polymorphic: true

    def dependent?
      return false unless self.class.column_names.include?("depends_on_recording_id")

      depends_on_recording_id.present?
    end

    def self.recordable_type_label
      RecordingStudioAccessible::Copy.t("recordables.access.label", default: LABEL)
    end

    class << self
      alias recording_studio_type_label recordable_type_label
    end

    def recordable_name
      actor_name = actor.respond_to?(:name) ? actor.name.to_s.squish.presence : nil
      actor_text =
        if actor_name.present?
          suffix = actor.class.name.demodulize
          "#{actor_name} (#{suffix})"
        else
          RecordingStudioAccessible::Copy.t(
            "errors.unknown_actor",
            default: "Unknown actor"
          )
        end

      RecordingStudioAccessible::Copy.t(
        "recordables.access.name",
        default: NAME_DEFAULT,
        role: role,
        actor: actor_text
      )
    end

    alias recording_studio_label recordable_name
  end
end
