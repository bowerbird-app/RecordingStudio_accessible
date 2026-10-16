# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class ApproveAccessRequest < BaseService
      include AccessRecordLifecycle

      def initialize(request_recording:, manager_actor: nil, role: nil, controller: nil)
        @request_recording = request_recording
        @manager_actor = manager_actor
        @role = role.to_s.strip.presence
        @controller = controller
      end

      private

      def perform
        validation = validate_request
        return validation unless validation == true

        approved = nil
        grant_error = nil
        RecordingStudio::Recording.transaction do
          target.lock!
          @request_recording.lock!
          @request_recording.reload
          unless pending_snapshot?
            grant_error = copy("errors.access_request_not_pending")
            raise ActiveRecord::Rollback
          end

          grant = GrantRecordingAccess.call(
            recording: target,
            actor: snapshot.actor,
            role: @role,
            manager_actor: manager,
            controller: @controller
          )
          unless grant.success?
            grant_error = grant.error
            raise ActiveRecord::Rollback
          end

          approved = revise_approved!(grant.value)
        end
        return failure(grant_error) if grant_error

        notify_granted
        Hooks.trigger(:access_request_approved, approved)
        success(approved)
      rescue ActiveRecord::RecordInvalid => e
        failure(e.message, errors: e.record.errors.full_messages)
      rescue StandardError => e
        failure(e)
      end

      def validate_request
        return failure(copy("errors.access_request_required")) unless request_recording?
        return failure(copy("errors.access_request_not_pending")) unless pending_snapshot?
        return failure(copy("errors.not_authorized")) unless manager_allowed?
        return failure(copy("errors.role_invalid")) unless approval_role_allowed?

        true
      end

      def approval_role_allowed?
        AccessRequestRoles.allowed?(recording: target, action: snapshot.action, role: @role)
      end

      def revise_approved!(access_recording)
        revised = nil
        AccessRequestCreationContext.allow do
          revised = root_recording.revise(@request_recording, actor: manager) do |request|
            request.role = @role
            request.status = "approved"
            request.access_recording_id = access_recording.id
          end
        end
        revised.log_event!(action: RecordingStudio::AccessRequest::EVENT_APPROVED, actor: manager)
        revised
      end

      def notify_granted
        RecordingStudioAccessible.configuration.notify_access_granted(
          controller: @controller,
          recording: target,
          actor: snapshot.actor,
          role: @role,
          manager_actor: manager
        )
      end

      def request_recording?
        @request_recording&.recordable_type == "RecordingStudio::AccessRequest" && target.present?
      end

      def pending_snapshot?
        snapshot&.pending?
      end

      def snapshot
        @request_recording&.recordable
      end

      def target
        @request_recording&.parent_recording
      end

      def manager_allowed?
        AccessManagementPolicy.allowed?(recording: target, actor: manager, controller: @controller)
      end

      def manager
        @manager ||= effective_manager_actor(manager_actor: @manager_actor, controller: @controller)
      end

      def root_recording
        RecordingStudio.root_recording_or_self(target || @request_recording)
      end

      def service_args
        { request_recording_id: @request_recording&.id, manager_actor_gid: global_id_string_for(manager) }
      end
    end
  end
end
