# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    # First :admin on an empty owned root, or on an empty accessible child under
    # a shared root, via the same write path as grant_access.
    class BootstrapOwnerAccess < BaseService
      include AccessRecordLifecycle
      include AccessGrantWriter

      ALREADY_BOOTSTRAPPED_MESSAGE =
        "Access already exists; use grant_access with a manager_actor"
      UNSUPPORTED_RECORDING_MESSAGE =
        "Bootstrap is only allowed on an empty owned root or an empty accessible child under a shared root"
      RECORDING_NOT_PERSISTED_MESSAGE = "Recording must be persisted"
      ACTOR_NOT_PERSISTED_MESSAGE = "Actor must be persisted"

      def initialize(recording:, actor:)
        @recording = recording
        @actor = actor
        @role = "admin"
        @manager_actor = actor
      end

      private

      attr_reader :manager_actor

      def perform
        validation_result = validate_request
        return validation_result unless validation_result == true

        ensure_current_impersonator_accessor!
        bootstrap_access_recording!
      rescue ActiveRecord::RecordInvalid => e
        failure(e.message, errors: e.record.errors.full_messages)
      rescue StandardError => e
        failure(e)
      end

      def validate_request
        presence_result = validate_presence_and_persistence!
        return presence_result unless presence_result == true

        # 0.6.1 required root_recording? here ("Recording must be a root
        # recording"), so a Profile under shared People never reached
        # shared-root denial or a grant. Shared-root rejection stays first;
        # owned roots and shared-forest children are allowed next.
        target_result = validate_bootstrap_target!
        return target_result unless target_result == true
        return failure("Actor type is not allowed for access") unless allowed_access_actor_type?

        true
      end

      def validate_presence_and_persistence!
        return failure("Recording is required") unless @recording
        return failure(RECORDING_NOT_PERSISTED_MESSAGE) unless persisted_record?(@recording)
        return failure("Actor is required") unless @actor
        return failure(ACTOR_NOT_PERSISTED_MESSAGE) unless persisted_record?(@actor)

        true
      end

      def validate_bootstrap_target!
        shared_root_result = reject_shared_root_target!(@recording)
        return shared_root_result unless shared_root_result == true
        return failure(UNSUPPORTED_RECORDING_MESSAGE) unless bootstrap_recording_shape?
        return failure("Direct access is not enabled for this recording") unless access_management_allowed?(@recording)

        true
      end

      def bootstrap_recording_shape?
        owned_root_target? || shared_forest_accessible_child?
      end

      def owned_root_target?
        root_recording_target? && !RecordingStudioAccessible::SharedRootAccess.target?(@recording)
      end

      def shared_forest_accessible_child?
        return false if root_recording_target?
        return false unless defined?(::RecordingStudio)

        if RecordingStudio.respond_to?(:shared_root_tree?)
          RecordingStudio.shared_root_tree?(@recording)
        else
          shared_forest_child_via_root?
        end
      rescue StandardError
        false
      end

      def shared_forest_child_via_root?
        root = RecordingStudio.root_recording_or_self(@recording)
        return false if root.blank?
        return false if root.id == @recording.id

        RecordingStudioAccessible::SharedRootAccess.target?(root)
      end

      def bootstrap_access_recording!
        result = nil
        RecordingStudio::Recording.transaction do
          lock_grant_scope!
          holders = active_direct_access_holders.to_a
          result = if holders.any?
                     existing = existing_owner_grant(holders)
                     existing ? success(existing) : failure(ALREADY_BOOTSTRAPPED_MESSAGE)
                   else
                     success(create_access_recording)
                   end
        end
        result
      end

      def existing_owner_grant(holders)
        return unless holders.size == 1

        access_recording = holders.first
        access = access_recording.recordable
        return unless access&.role.to_s == "admin"
        return unless same_actor?(access.actor, @actor)

        access_recording
      end

      def active_direct_access_holders
        RecordingStudioAccessible::DirectAccessQuery.access_recordings_for(@recording)
      end

      def root_recording_target?
        return false unless defined?(::RecordingStudio)
        return false unless @recording.respond_to?(:id) && @recording.id.present?

        RecordingStudio.root_recording?(@recording)
      rescue StandardError
        false
      end

      def persisted_record?(record)
        return false unless record.respond_to?(:id) && record.id.present?
        return true unless record.respond_to?(:persisted?)

        record.persisted?
      end

      def same_actor?(left, right)
        return false if left.nil? || right.nil?

        RecordingStudioAccessible::ActorType.for(left) == RecordingStudioAccessible::ActorType.for(right) &&
          left.id == right.id
      end

      def allowed_access_actor_type?
        RecordingStudioAccessible.configuration.allowed_access_actor_type?(@actor)
      end

      def service_args
        {
          recording_id: @recording&.id,
          actor_gid: global_id_string_for(@actor),
          role: @role,
          manager_actor_gid: global_id_string_for(manager_actor)
        }
      end
    end
  end
end
