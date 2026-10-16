# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class TransitionAccessRequest < BaseService
      include AccessRecordLifecycle

      def initialize(request_recording:, status:, manager_actor: nil, role: nil, review_note: nil, controller: nil)
        @request_recording = request_recording
        @status = status.to_s
        @manager_actor = manager_actor
        @role = role.to_s.strip.presence
        @review_note = review_note.to_s.strip.presence
        @controller = controller
      end

      private

      def perform
        validation = validate_request
        return validation unless validation == true

        revised, error = write_transition
        return failure(error) if error

        finish_transition(revised)
        success(revised)
      rescue ActiveRecord::RecordInvalid => e
        failure(e.message, errors: e.record.errors.full_messages)
      rescue ActiveRecord::RecordNotUnique
        failure(copy("errors.duplicate_access_request"))
      rescue StandardError => e
        unexpected_failure(e)
      end

      def validate_request
        return failure(copy("errors.access_request_required")) unless request_recording?
        return failure(copy("errors.access_request_transition")) if transition_blocked?
        return failure(copy("errors.not_authorized")) unless manager_allowed?
        return failure(copy("errors.role_invalid")) if role_rejected?
        return failure(copy("errors.role_exceeds_manager")) if role_above_manager?
        return failure(copy("errors.review_note_too_long")) if note_too_long?
        return failure(copy("errors.duplicate_access_request")) if pending_conflict?

        true
      end

      def write_transition
        revised = nil
        error = nil
        RecordingStudio::Recording.transaction do
          lock_rows!
          error = locked_failure || apply_effects!
          raise ActiveRecord::Rollback if error

          revised = revise_request!
        end
        [revised, error]
      end

      def lock_rows!
        target.lock!
        @request_recording.lock!
        @request_recording.reload
      end

      def locked_failure
        return copy("errors.access_request_transition") if transition_blocked?
        return copy("errors.duplicate_access_request") if pending_conflict?

        nil
      end

      def apply_effects!
        error = release_grant! if leaving_approved?
        return error if error

        grant_access! if approving?
      end

      def release_grant!
        recording = current_grant
        return if recording.blank?

        result = RevokeRecordingAccess.call(**revoke_args(recording))
        result.error unless result.success?
      end

      def revoke_args(recording)
        { recording: target, access_recording: recording, manager_actor: manager, controller: @controller }
      end

      def grant_access!
        result = RecordingStudioAccessible.grant_access(**grant_args)
        return result.error unless result.success?

        @access_recording = result.value
        nil
      end

      def grant_args
        { recording: target, actor: snapshot.actor, role: @role, manager_actor: manager }
      end

      def revise_request!
        snapshot.release_pending_key!
        revised = nil
        AccessRequestCreationContext.allow do
          revised = root_recording.revise(@request_recording, actor: manager) { |request| apply_snapshot(request) }
        end
        revised.log_event!(action: AccessRequestTransitions.event_for(@status), actor: manager)
        revised
      end

      def apply_snapshot(request)
        request.status = @status
        request.role = next_role(request)
        request.review_note = denying? ? @review_note : nil
        request.access_recording_id = approving? ? @access_recording.id : nil
        request.pending_key = reopening? ? pending_key_for(request) : nil
      end

      def pending_key_for(request)
        RecordingStudio::AccessRequest.pending_key_for(target_id: request.target_recording_id, actor: request.actor)
      end

      def finish_transition(revised)
        notify_approved if approving?
        notify_denied(revised) if denying?
        Hooks.trigger(AccessRequestTransitions.hook_for(@status), revised)
      end

      def notify_approved
        RecordingStudioAccessible.configuration.notify_access_granted(**granted_args)
      end

      def granted_args
        { controller: @controller, recording: target, actor: snapshot.actor, role: @role, manager_actor: manager }
      end

      def notify_denied(revised)
        RecordingStudioAccessible.configuration.notify_access_request_denied(**denied_args(revised))
      end

      def denied_args(revised)
        {
          controller: @controller, request_recording: revised, recording: target,
          actor: snapshot.actor, review_note: @review_note
        }
      end

      def next_role(request)
        return @role if approving?
        return if reopening?

        request.role
      end

      def current_grant
        id = snapshot&.access_recording_id
        return if id.blank?

        RecordingStudio::Recording.unscoped.find_by(id: id)
      end

      def transition_blocked?
        !AccessRequestTransitions.allowed?(from: snapshot&.status, to: @status)
      end

      def role_rejected?
        approving? && !AccessRequestRoles.allowed?(recording: target, action: snapshot.action, role: @role)
      end

      def role_above_manager?
        approving? && !RoleCeiling.allowed?(recording: target, manager: manager, role: @role)
      end

      def note_too_long?
        denying? && @review_note.to_s.length > RecordingStudio::AccessRequest::NOTE_MAX
      end

      def pending_conflict?
        return false unless reopening?

        AccessRequestQuery.pending_for(recording: target, actor: snapshot.actor).where.not(id: @request_recording.id).exists?
      end

      def request_recording?
        @request_recording&.recordable_type == "RecordingStudio::AccessRequest" && target.present?
      end

      def manager_allowed?
        AccessManagementPolicy.allowed?(recording: target, actor: manager, controller: @controller)
      end

      def approving?
        @status == "approved"
      end

      def denying?
        @status == "denied"
      end

      def reopening?
        @status == "pending"
      end

      def leaving_approved?
        snapshot&.status == "approved"
      end

      def snapshot
        @request_recording&.recordable
      end

      def target
        @request_recording&.parent_recording
      end

      def manager
        @manager ||= effective_manager_actor(manager_actor: @manager_actor, controller: @controller)
      end

      def root_recording
        RecordingStudio.root_recording_or_self(target || @request_recording)
      end

      def service_args
        { request_recording_id: @request_recording&.id, status: @status, manager_actor_gid: global_id_string_for(manager) }
      end
    end
  end
end
