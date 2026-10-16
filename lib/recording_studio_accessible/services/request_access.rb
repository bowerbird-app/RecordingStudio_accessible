# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class RequestAccess < BaseService
      def initialize(recording:, actor:, role: nil, action: nil, message: nil, controller: nil)
        @recording = recording
        @actor = actor
        @role = role.to_s.strip.presence
        @action = action.to_s.strip.presence
        @message = message.to_s.strip.presence
        @controller = controller
      end

      private

      def perform
        validation = validate_request
        return validation unless validation == true

        request_recording = nil
        already_granted = false
        RecordingStudio::Recording.transaction do
          @recording.lock!
          if already_granted?
            already_granted = true
            next
          end

          request_recording = write_request!
        end
        return success(nil) if already_granted

        notify_and_hook(request_recording)
        success(request_recording)
      rescue ActiveRecord::RecordInvalid => e
        failure(e.message, errors: e.record.errors.full_messages)
      rescue ActiveRecord::RecordNotUnique
        failure(copy("errors.duplicate_access_request"))
      rescue StandardError => e
        unexpected_failure(e)
      end

      def validate_request
        return failure(copy("errors.recording_required")) unless @recording
        return failure(copy("errors.actor_required")) unless persisted_actor?
        return failure(copy("errors.actor_type_not_allowed")) unless allowed_actor_type?
        return failure(copy("errors.role_invalid")) if rejected_role?
        return failure(copy("errors.message_too_long")) if message_too_long?
        return failure(copy("errors.action_too_long")) if action_too_long?
        return failure(copy("errors.grant_denied")) if SharedRootAccess.target?(@recording)
        return failure(copy("errors.direct_access_not_enabled")) unless parent_allowed?
        return failure(copy("requests.errors.gate_unavailable")) if gate_unsatisfied?

        true
      end

      def message_too_long?
        @message.to_s.length > RecordingStudio::AccessRequest::MESSAGE_MAX
      end

      def action_too_long?
        @action.to_s.length > RecordingStudio::AccessRequest::ACTION_MAX
      end

      def persisted_actor?
        @actor.respond_to?(:id) && @actor.id.present? && (!@actor.respond_to?(:persisted?) || @actor.persisted?)
      end

      def allowed_actor_type?
        RecordingStudioAccessible.configuration.allowed_access_actor_type?(@actor)
      end

      def parent_allowed?
        Compatibility.access_request_parent_allowed?(@recording)
      end

      def rejected_role?
        @role.present? && !RecordingStudioAccessible.role_valid_for?(@recording, @role)
      end

      def already_granted?
        return false if @role.blank?

        RecordingStudioAccessible.authorized?(actor: @actor, recording: @recording, role: @role)
      end

      def write_request!
        pending = AccessRequestQuery.pending_for(recording: @recording, actor: @actor).first
        pending ? revise_pending!(pending) : create_request!
      end

      def create_request!
        recording = nil
        AccessRequestCreationContext.allow do
          recording = root_recording.record(
            RecordingStudio::AccessRequest,
            actor: @actor,
            parent_recording: @recording
          ) do |request|
            assign_snapshot(request)
          end
        end
        recording.log_event!(action: RecordingStudio::AccessRequest::EVENT_SUBMITTED, actor: @actor)
        recording
      end

      def revise_pending!(request_recording)
        request_recording.recordable.release_pending_key!
        revised = nil
        AccessRequestCreationContext.allow do
          revised = root_recording.revise(request_recording, actor: @actor) do |request|
            assign_snapshot(request)
            request.review_note = nil
          end
        end
        revised.log_event!(action: RecordingStudio::AccessRequest::EVENT_RESUBMITTED, actor: @actor)
        revised
      end

      def assign_snapshot(request)
        request.actor = @actor
        request.role = @role
        request.action = @action
        request.message = @message
        request.status = "pending"
        request.target_recording_id = @recording.id
        request.pending_key = RecordingStudio::AccessRequest.pending_key_for(target_id: @recording.id, actor: @actor)
        request.gate_metadata = gate_metadata
      end

      def gate_unsatisfied?
        AccessRequestGate.blocking?(
          AccessRequestGate.for_action(@action),
          recording: @recording,
          actor: @actor,
          request: http_request
        )
      end

      def http_request
        @controller.request if @controller.respond_to?(:request)
      rescue StandardError
        nil
      end

      def gate_metadata
        AccessRequestGateMetadata.clean(
          AccessRequestGate.metadata_for(
            AccessRequestGate.for_action(@action),
            recording: @recording,
            actor: @actor
          )
        )
      end

      def notify_and_hook(request_recording)
        RecordingStudioAccessible.configuration.notify_access_request_submitted(
          controller: @controller,
          request_recording: request_recording,
          recording: @recording,
          actor: @actor,
          role: @role
        )
        Hooks.trigger(:access_request_submitted, request_recording)
      end

      def root_recording
        RecordingStudio.root_recording_or_self(@recording)
      end

      def service_args
        {
          recording_id: @recording&.id,
          actor_gid: global_id_string_for(@actor),
          role: @role,
          action: @action
        }
      end
    end
  end
end
