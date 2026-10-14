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
    # I18n interpolation tokens use %{name}, not %<name>s.
    NAME_DEFAULT = "Access: %{role} — %{actor}" # rubocop:disable Style/FormatStringToken

    # recording_studio_recordable captures label at class load; keep English here.
    recording_studio_recordable label: LABEL, root: false if respond_to?(:recording_studio_recordable)

    belongs_to :actor, polymorphic: true

    def dependent?
      return false unless self.class.column_names.include?("depends_on_recording_id")

      depends_on_recording_id.present?
    end

    def self.recordable_type_label
      RecordingStudioAccessible::Copy.t("recordables.access.label")
    end

    class << self
      alias recording_studio_type_label recordable_type_label
    end

    def recordable_name
      RecordingStudioAccessible::Copy.t(
        "recordables.access.name",
        role: role,
        actor: access_actor_text
      )
    end

    def access_actor_text
      actor_name = actor.respond_to?(:name) ? actor.name.to_s.squish.presence : nil
      return "#{actor_name} (#{actor.class.name.demodulize})" if actor_name.present?

      RecordingStudioAccessible::Copy.t("errors.unknown_actor")
    end
    private :access_actor_text

    alias recording_studio_label recordable_name
  end
end
