# frozen_string_literal: true

require "active_support/concern"

module RecordingStudioAccessible
  module AccessRecordingCreationGuard
    DUPLICATE_ACCESS_RECORDING_ERROR = "Only one direct access grant is allowed per actor under the same parent"

    extend ActiveSupport::Concern

    included do
      validate :prevent_unsupported_access_recording_creation, on: :create
      validate :prevent_duplicate_active_access_recording, on: :create
    end

    private

    def prevent_unsupported_access_recording_creation
      return unless access_recordable?
      return unless access_placement_enabled?
      return if RecordingStudioAccessible::AccessCreationContext.allowed?

      create_via_grant_access_error =
        "Create access grants through RecordingStudioAccessible.grant_access"
      errors.add(
        :base,
        create_via_grant_access_error,
        message: Copy.t("errors.create_via_grant_access", default: create_via_grant_access_error)
      )
    end

    def prevent_duplicate_active_access_recording
      return unless access_recordable?
      return if parent_recording.blank?

      access = access_recordable_instance
      actor = access&.actor
      return unless actor

      actor_type = access.actor_type.presence || RecordingStudioAccessible::ActorType.for(actor)
      actor_id = access.actor_id || actor.id

      duplicate_scope = self.class.unscoped
      duplicate_scope = duplicate_scope.where(trashed_at: nil) if has_attribute?(:trashed_at)

      duplicate_exists = duplicate_scope
                         .where(parent_recording_id: parent_recording_id, recordable_type: "RecordingStudio::Access")
                         .where.not(id: id)
                         .joins(<<~SQL.squish)
                           INNER JOIN recording_studio_accesses
                             ON recording_studio_accesses.id = #{self.class.table_name}.recordable_id
                         SQL
                         .where(recording_studio_accesses: { actor_type: actor_type, actor_id: actor_id })
                         .exists?

      return unless duplicate_exists

      errors.add(
        :base,
        DUPLICATE_ACCESS_RECORDING_ERROR,
        message: Copy.t("errors.duplicate_access_recording", default: DUPLICATE_ACCESS_RECORDING_ERROR)
      )
    end

    def access_recordable?
      return true if recordable_type == "RecordingStudio::Access"
      return false unless defined?(::RecordingStudio::Access)
      return true if recordable.is_a?(::RecordingStudio::Access)

      association(:recordable).target.is_a?(::RecordingStudio::Access)
    end

    def access_recordable_instance
      return recordable if recordable.is_a?(::RecordingStudio::Access)

      association(:recordable).target
    end

    def access_placement_enabled?
      return false if parent_recording.blank?

      if shared_root_parent?(parent_recording)
        denied = RecordingStudioAccessible::SharedRootAccess::GRANT_DENIED_MESSAGE
        errors.add(
          :parent_recording,
          denied,
          message: Copy.t("errors.grant_denied", default: denied)
        )
        return false
      end

      return true if RecordingStudioAccessible::Compatibility.access_parent_allowed?(parent_recording)

      access_children_not_allowed = "does not allow RecordingStudio::Access children"
      errors.add(
        :parent_recording,
        access_children_not_allowed,
        message: Copy.t("errors.access_children_not_allowed", default: access_children_not_allowed)
      )
      false
    end

    def shared_root_parent?(parent_recording)
      return false unless parent_recording.respond_to?(:recordable_type)

      RecordingStudioAccessible::SharedRootAccess.target?(parent_recording)
    end
  end
end
