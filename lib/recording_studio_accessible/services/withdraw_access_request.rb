# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class WithdrawAccessRequest < BaseService
      include AccessRecordLifecycle

      def initialize(request_recording:, actor: nil, controller: nil)
        @request_recording = request_recording
        @actor = actor
        @controller = controller
      end

      private

      def perform
        validation = validate_request
        return validation unless validation == true

        withdrawn = RecordingStudio::Recording.transaction do
          @request_recording.lock!
          @request_recording.reload
          raise ActiveRecord::Rollback unless pending_snapshot?

          revise_withdrawn!
        end
        return failure(copy("errors.access_request_not_pending")) unless withdrawn

        success(withdrawn)
      rescue ActiveRecord::RecordInvalid => e
        failure(e.message, errors: e.record.errors.full_messages)
      rescue StandardError => e
        failure(e)
      end

      def validate_request
        return failure(copy("errors.access_request_required")) unless request_recording?
        return failure(copy("errors.access_request_not_pending")) unless pending_snapshot?
        return failure(copy("errors.actor_required")) unless acting_actor
        return failure(copy("errors.not_authorized")) unless allowed?

        true
      end

      def revise_withdrawn!
        revised = nil
        AccessRequestCreationContext.allow do
          revised = root_recording.revise(@request_recording, actor: acting_actor) do |request|
            request.status = "withdrawn"
          end
        end
        revised.log_event!(action: RecordingStudio::AccessRequest::EVENT_WITHDRAWN, actor: acting_actor)
        revised
      end

      def allowed?
        owns_request? || manager_allowed?
      end

      def owns_request?
        owner = snapshot&.actor
        return false unless owner && acting_actor

        ActorType.for(owner) == ActorType.for(acting_actor) && owner.id == acting_actor.id
      end

      def manager_allowed?
        AccessManagementPolicy.allowed?(recording: target, actor: acting_actor, controller: @controller)
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

      def acting_actor
        @acting_actor ||= effective_manager_actor(manager_actor: @actor, controller: @controller)
      end

      def root_recording
        RecordingStudio.root_recording_or_self(target || @request_recording)
      end
    end
  end
end
