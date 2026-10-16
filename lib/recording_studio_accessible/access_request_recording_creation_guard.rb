# frozen_string_literal: true

require "active_support/concern"

module RecordingStudioAccessible
  module AccessRequestRecordingCreationGuard
    extend ActiveSupport::Concern

    included do
      validate :prevent_unsupported_access_request_recording_creation, on: :create
      validate :prevent_duplicate_pending_access_request, on: :create
    end

    private

    def prevent_unsupported_access_request_recording_creation
      return unless access_request_recordable?
      return unless access_request_placement_enabled?
      return if RecordingStudioAccessible::AccessRequestCreationContext.allowed?

      errors.add(:base, Copy.t("errors.create_via_request_access"))
    end

    def prevent_duplicate_pending_access_request
      identity = pending_actor_identity
      return unless identity
      return unless pending_access_request_exists?(*identity)

      errors.add(:base, Copy.t("errors.duplicate_access_request"))
    end

    def pending_actor_identity
      request = pending_request_snapshot
      return unless request

      actor_identity(request)
    end

    def pending_request_snapshot
      return unless access_request_recordable?
      return if parent_recording.blank?

      request = access_request_recordable_instance
      request if request&.status.to_s == "pending" && request.actor
    end

    def actor_identity(request)
      actor = request.actor
      actor_type = request.actor_type.presence || RecordingStudioAccessible::ActorType.for(actor)
      actor_id = request.actor_id || actor.id
      return if actor_type.blank? || actor_id.blank?

      [actor_type, actor_id]
    end

    def pending_access_request_exists?(actor_type, actor_id)
      kept_recordings
        .where(parent_recording_id: parent_recording_id, recordable_type: AccessRequestQuery::TYPE)
        .where.not(id: id)
        .joins(AccessRequestQuery::JOIN_SQL)
        .where(pending_actor_clause(actor_type, actor_id))
        .exists?
    end

    def kept_recordings
      scope = self.class.unscoped
      return scope unless has_attribute?(:trashed_at)

      scope.where(self.class.recording_studio_trashable_kept_sql)
    end

    def pending_actor_clause(actor_type, actor_id)
      { recording_studio_access_requests: { actor_type: actor_type, actor_id: actor_id, status: "pending" } }
    end

    def access_request_recordable?
      return true if recordable_type == AccessRequestQuery::TYPE
      return false unless defined?(::RecordingStudio::AccessRequest)
      return true if recordable.is_a?(::RecordingStudio::AccessRequest)

      association(:recordable).target.is_a?(::RecordingStudio::AccessRequest)
    end

    def access_request_recordable_instance
      return recordable if recordable.is_a?(::RecordingStudio::AccessRequest)

      association(:recordable).target
    end

    def access_request_placement_enabled?
      return false if parent_recording.blank?

      if shared_access_request_parent?(parent_recording)
        errors.add(:parent_recording, Copy.t("errors.grant_denied"))
        return false
      end

      return true if RecordingStudioAccessible::Compatibility.access_request_parent_allowed?(parent_recording)

      errors.add(:parent_recording, Copy.t("errors.access_request_children_not_allowed"))
      false
    end

    def shared_access_request_parent?(parent_recording)
      return false unless parent_recording.respond_to?(:recordable_type)

      RecordingStudioAccessible::SharedRootAccess.target?(parent_recording)
    end
  end
end
