# frozen_string_literal: true

require "recording_studio_accessible/extracted/recording_studio/access_roles"

module RecordingStudioAccessible
  # Relationship between Access recordings: a grant may depend on another
  # Access recording (the manager grant) on the same root.
  #
  # Authorize-time checks own the invariant and fail closed. Voiding a
  # dependent grant when the manager dies or is downgraded is necessary but
  # not sufficient — `authorized?` / `role_for` must not honor a dependent
  # grant whose manager is missing, trashed, off-root, or weaker. Moving the
  # manager Access recording voids dependents in place; same-root authorize
  # still succeeds until that void job runs.
  module DependentAccess
    MISSING_COLUMN_MESSAGE = "Dependent grants require the depends_on_recording_id column"
    MISSING_MANAGER_MESSAGE = "Manager access grant is missing or inactive"
    NOT_ACCESS_SAME_ROOT_MESSAGE = "Manager must be an Access recording on the same root"
    ROLE_EXCEEDS_MESSAGE = "Dependent role cannot exceed the manager grant's role"
    CYCLE_MESSAGE = "Dependent access cannot depend on itself or form a cycle"

    class << self
      def column_available?
        return false unless defined?(::RecordingStudio::Access)
        return false unless RecordingStudio::Access.respond_to?(:column_names)

        RecordingStudio::Access.column_names.include?("depends_on_recording_id")
      rescue StandardError
        false
      end

      def effective?(access_recording, seen = nil)
        return false if access_recording.nil?

        access = recordable_for(access_recording)
        manager_id = depends_on_recording_id_for(access)
        return true if manager_id.blank?

        recording_id = access_recording.respond_to?(:id) ? access_recording.id : nil
        seen_ids = seen || {}
        return false if recording_id && seen_ids[recording_id]

        next_seen = recording_id ? seen_ids.merge(recording_id => true) : seen_ids
        manager = find_recording(manager_id)
        return false unless valid_manager?(manager, relative_to: access_recording)
        return false unless role_capped?(dependent_role: access&.role, manager: manager)
        return false unless effective?(manager, next_seen)

        true
      end

      def grant_error(target_recording:, role:, depends_on:, dependent_recording: nil)
        return if depends_on.nil?

        return MISSING_COLUMN_MESSAGE unless column_available?

        manager = resolve_recording(depends_on)
        return MISSING_MANAGER_MESSAGE unless manager
        return MISSING_MANAGER_MESSAGE unless active_recording?(manager)
        return NOT_ACCESS_SAME_ROOT_MESSAGE unless access_recording?(manager)
        return NOT_ACCESS_SAME_ROOT_MESSAGE unless same_root?(target_recording, manager)
        return CYCLE_MESSAGE if cyclic_dependency?(depends_on: manager, dependent_recording: dependent_recording)
        return ROLE_EXCEEDS_MESSAGE unless role_capped?(dependent_role: role, manager: manager)

        nil
      end

      def manager_recording_for(access_recording)
        access = recordable_for(access_recording)
        manager_id = depends_on_recording_id_for(access)
        return if manager_id.blank?

        find_recording(manager_id)
      end

      private

      def valid_manager?(manager, relative_to:)
        return false unless manager
        return false unless active_recording?(manager)
        return false unless access_recording?(manager)
        return false unless same_root?(relative_to, manager)

        true
      end

      def role_capped?(dependent_role:, manager:)
        manager_role = recordable_for(manager)&.role
        return false unless RecordingStudio::AccessRoles.value_for(manager_role)
        return false unless RecordingStudio::AccessRoles.value_for(dependent_role)

        RecordingStudio::AccessRoles.satisfies?(role: manager_role, minimum_role: dependent_role)
      end

      def cyclic_dependency?(depends_on:, dependent_recording:)
        return false unless dependent_recording.respond_to?(:id) && dependent_recording.id.present?
        return true if depends_on.id == dependent_recording.id

        seen = { dependent_recording.id => true, depends_on.id => true }
        current = manager_recording_for(depends_on)
        while current
          return true if seen[current.id]

          seen[current.id] = true
          current = manager_recording_for(current)
        end

        false
      end

      def access_recording?(recording)
        return true if recording.respond_to?(:recordable_type) &&
                       recording.recordable_type == "RecordingStudio::Access"
        return true if defined?(::RecordingStudio::Access) &&
                       recording.respond_to?(:recordable) &&
                       recording.recordable.is_a?(::RecordingStudio::Access)

        false
      end

      def same_root?(left, right)
        return false unless left && right
        return false unless defined?(::RecordingStudio) && RecordingStudio.respond_to?(:root_recording_id_for)

        RecordingStudio.root_recording_id_for(left) == RecordingStudio.root_recording_id_for(right)
      rescue StandardError
        false
      end

      def active_recording?(recording)
        return false unless recording
        return true unless recording.respond_to?(:trashed_at)

        recording.trashed_at.nil?
      end

      def recordable_for(recording)
        return unless recording.respond_to?(:recordable)

        recording.recordable
      end

      def depends_on_recording_id_for(access)
        return unless access
        return unless access.respond_to?(:depends_on_recording_id)

        access.depends_on_recording_id
      end

      def resolve_recording(depends_on)
        id = depends_on.respond_to?(:id) ? depends_on.id : depends_on
        find_recording(id)
      end

      def find_recording(id)
        return if id.blank?
        return unless defined?(::RecordingStudio::Recording)
        return unless RecordingStudio::Recording.respond_to?(:unscoped)

        RecordingStudio::Recording.unscoped.find_by(id: id)
      rescue StandardError
        nil
      end
    end
  end
end
