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

        existing_result = refuse_existing_self_delegated_grant!
        return existing_result unless existing_result == true
        return failure(copy("errors.self_delegated_depends_on_required")) if @depends_on.nil?
        return failure(copy("errors.self_delegated_depends_on_invalid")) unless self_delegated_depends_on_own_grant?

        true
      end

      def refuse_existing_self_delegated_grant!
        existing = existing_access_recordings.first
        return true unless existing

        @access_recording = existing
        return failure(copy("errors.role_exceeds_manager")) unless existing_grant_within_manager?

        failure(copy("errors.self_delegated_existing_grant"))
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
