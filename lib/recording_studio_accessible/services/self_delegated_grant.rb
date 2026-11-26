# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    module SelfDelegatedGrant
      private

      def validate_self_delegated_target!
        target_result = validate_grant_target!(@recording)
        return target_result unless target_result == true

        held = RoleCeiling.held_role(@recording, manager_actor)
        return failure(copy("errors.self_delegated_not_a_member")) if held.blank?
        return failure(copy("errors.dependent_missing_manager")) if @depends_on.nil?
        return failure(copy("errors.self_delegated_depends_on_invalid")) unless self_delegated_depends_on_own_grant?

        existing_result = reuse_or_refuse_existing_self_delegated_grant
        return existing_result unless existing_result == true

        true
      end

      def reuse_or_refuse_existing_self_delegated_grant
        existing = existing_access_recordings.first
        return true unless existing
        # Reconnects stay idempotent only while still within the member's own role.
        return success(existing) if same_self_delegated_grant?(existing) && role_within_manager?

        existing_role = existing.recordable.role
        unless RoleCeiling.allowed?(recording: @recording, manager: manager_actor, role: existing_role)
          return failure(copy("errors.role_exceeds_manager"))
        end

        failure(copy("errors.self_delegated_existing_grant"))
      end

      def same_self_delegated_grant?(existing)
        access = existing.recordable
        return false unless access
        return false unless access.role.to_s == @role.to_s
        return false unless @depends_on.respond_to?(:id)

        access.depends_on_recording_id == @depends_on.id
      end

      def self_delegated_depends_on_own_grant?
        return false unless @depends_on.respond_to?(:id) && @depends_on.id.present?

        DirectAccessQuery.access_recordings_for_actor(
          recording: @recording,
          actor: manager_actor
        ).exists?(id: @depends_on.id)
      end
    end
  end
end
