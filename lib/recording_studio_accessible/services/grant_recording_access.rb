# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class GrantRecordingAccess < BaseService
      include AccessRecordLifecycle

      def initialize(recording:, actor:, role:, manager_actor: nil, controller: nil)
        @recording = recording
        @actor = actor
        @role = role.to_s
        @manager_actor = manager_actor
        @controller = controller
      end

      private

      def perform
        validation_result = validate_request
        return validation_result unless validation_result == true

        ensure_current_impersonator_accessor!

        access_recording = upsert_access_recording!

        success(access_recording)
      rescue ActiveRecord::RecordInvalid => e
        failure(e.message, errors: e.record.errors.full_messages)
      rescue StandardError => e
        failure(e)
      end

      def validate_request
        return failure("Recording is required") unless @recording
        return failure("Actor is required") unless @actor

        authorization_result = authorize_access_management!(
          recording: @recording,
          manager_actor: @manager_actor,
          controller: @controller
        )
        return authorization_result unless authorization_result == true
        return failure("Direct access is not enabled for this recording") unless access_enabled?
        return failure("Actor type is not allowed for access") unless allowed_access_actor_type?
        return failure("Role is invalid") unless valid_role?

        true
      end

      def upsert_access_recording!
        RecordingStudio::Recording.transaction do
          lock_grant_scope!

          existing_recordings = existing_access_recordings.to_a
          access_recording = existing_recordings.first

          if access_recording
            update_existing_access_recording(access_recording, existing_recordings)
          else
            create_access_recording
          end
        end
      end

      def update_existing_access_recording(access_recording, existing_recordings)
        deduplicate_access_recordings!(existing_recordings.drop(1))

        RecordingStudioAccessible::AccessCreationContext.allow do
          root_recording.revise(access_recording, actor: @manager_actor) do |access|
            access.role = @role
          end
        end
      end

      def create_access_recording
        RecordingStudioAccessible::AccessCreationContext.allow do
          root_recording.record(
            RecordingStudio::Access,
            actor: @manager_actor,
            parent_recording: @recording
          ) do |access|
            access.actor = @actor
            access.role = @role
          end
        end
      end

      def service_args
        {
          recording_id: @recording&.id,
          actor_gid: global_id_string_for(@actor),
          role: @role,
          manager_actor_gid: global_id_string_for(@manager_actor)
        }
      end

      def valid_role?
        RecordingStudio::Access.roles.key?(@role)
      end

      def access_enabled?
        RecordingStudioAccessible::Compatibility.access_parent_allowed?(@recording)
      end

      def allowed_access_actor_type?
        RecordingStudioAccessible.configuration.allowed_access_actor_type?(@actor)
      end

      def root_recording
        RecordingStudio.root_recording_or_self(@recording)
      end

      def lock_grant_scope!
        @recording.lock!
      end

      def existing_access_recordings
        return RecordingStudio::Recording.none unless @actor

        RecordingStudioAccessible::DirectAccessQuery.access_recordings_for_actor(recording: @recording, actor: @actor)
      end

      def deduplicate_access_recordings!(access_recordings)
        access_recordings.each do |access_recording|
          destroy_access_recording!(access_recording, manager_actor: @manager_actor)
        end
      end
    end
  end
end
