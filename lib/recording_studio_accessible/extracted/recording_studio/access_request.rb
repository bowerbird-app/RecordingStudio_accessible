# frozen_string_literal: true

module RecordingStudio
  # Inbound request for access to a recording.
  #
  # Application code should not create AccessRequest rows directly. Use:
  #
  #   RecordingStudioAccessible.request_access(...)
  #
  class AccessRequest < ::ApplicationRecord
    self.table_name = "recording_studio_access_requests"
    include RecordingStudio::Recordable
    include RecordingStudioAccessible::AccessRequestCreationGuard

    STATUSES = %w[pending approved denied withdrawn].freeze
    MESSAGE_MAX = 2_000
    NOTE_MAX = 2_000
    ACTION_MAX = 120
    LABEL = "Access request"
    EVENT_SUBMITTED = "access_request_submitted"
    EVENT_RESUBMITTED = "resubmitted"
    EVENT_APPROVED = "approved"
    EVENT_DENIED = "denied"
    EVENT_WITHDRAWN = "withdrawn"
    EVENTS = [
      EVENT_SUBMITTED,
      EVENT_RESUBMITTED,
      EVENT_APPROVED,
      EVENT_DENIED,
      EVENT_WITHDRAWN
    ].freeze

    recording_studio_recordable label: LABEL, root: false if respond_to?(:recording_studio_recordable)

    belongs_to :actor, polymorphic: true

    validates :role, length: { maximum: 64 }, allow_nil: true
    validates :status, inclusion: { in: STATUSES }
    validates :message, length: { maximum: MESSAGE_MAX }, allow_nil: true
    validates :review_note, length: { maximum: NOTE_MAX }, allow_nil: true
    validates :action, length: { maximum: ACTION_MAX }, allow_nil: true

    def pending?
      status == "pending"
    end

    def self.recordable_type_label
      RecordingStudioAccessible::Copy.t("recordables.access_request.label")
    end

    class << self
      alias recording_studio_type_label recordable_type_label
    end

    def recordable_name
      return named_with_role if role.present?

      RecordingStudioAccessible::Copy.t("recordables.access_request.name_without_role", status: status)
    end

    def named_with_role
      RecordingStudioAccessible::Copy.t("recordables.access_request.name", role: role, status: status)
    end

    alias recording_studio_label recordable_name
  end
end
