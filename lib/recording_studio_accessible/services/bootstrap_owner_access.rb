# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    # One-shot first-owner grant on an empty owned root recording.
    #
    # Creates exactly one :admin Access grant for +actor+ through the same
    # write machinery as GrantRecordingAccess. Does not weaken the default
    # access_management_authorizer used by grant_access.
    class BootstrapOwnerAccess < BaseService
      include AccessRecordLifecycle
      include AccessGrantWriter

      ALREADY_BOOTSTRAPPED_MESSAGE =
        "Access already exists; use grant_access with a manager_actor".freeze
      NON_ROOT_MESSAGE = "Recording must be a root recording".freeze
      RECORDING_NOT_PERSISTED_MESSAGE = "Recording must be persisted".freeze
      ACTOR_NOT_PERSISTED_MESSAGE = "Actor must be persisted".freeze

      def initialize(recording:, actor:)
        @recording = recording
        @actor = actor
        @role = "admin"
        @manager_actor = actor
      end

      private

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
        return failure("Recording is required") unless @recording
        return failure(RECORDING_NOT_PERSISTED_MESSAGE) unless persisted_record?(@recording)
        return failure("Actor is required") unless @actor
        return failure(ACTOR_NOT_PERSISTED_MESSAGE) unless persisted_record?(@actor)
        return failure(NON_ROOT_MESSAGE) unless root_recording_target?

        shared_root_result = reject_shared_root_target!(@recording)
        return shared_root_result unless shared_root_result == true
        return failure("Direct access is not enabled for this recording") unless access_management_allowed?(@recording)
        return failure("Actor type is not allowed for access") unless allowed_access_actor_type?

        true
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
        return unless access
        return unless access.role.to_s == "admin"
        return unless same_actor?(access.actor, @actor)

        access_recording
      end

      def active_direct_access_holders
        RecordingStudioAccessible::DirectAccessQuery.access_recordings_for(@recording)
      end

      def root_recording_target?
        return false unless defined?(::RecordingStudio)
        return false unless @recording.respond_to?(:id) && @recording.id.present?

        if RecordingStudio.respond_to?(:root_recording?)
          RecordingStudio.root_recording?(@recording)
        else
          RecordingStudio.root_recording_id_for(@recording) == @recording.id
        end
      rescue StandardError
        false
      end

      def persisted_record?(record)
        return false unless record.respond_to?(:id) && record.id.present?
        return true unless record.respond_to?(:persisted?)

        record.persisted?
      end

      def same_actor?(left, right)
        return false unless left && right
        return true if left.equal?(right)
        return false unless left.respond_to?(:id) && right.respond_to?(:id)
        return false if left.id.blank? || right.id.blank?

        RecordingStudioAccessible::ActorType.for(left) == RecordingStudioAccessible::ActorType.for(right) &&
          left.id == right.id
      end

      def allowed_access_actor_type?
        RecordingStudioAccessible.configuration.allowed_access_actor_type?(@actor)
      end

      def manager_actor
        @manager_actor
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
