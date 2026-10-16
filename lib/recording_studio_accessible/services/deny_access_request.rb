# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class DenyAccessRequest < BaseService
      include AccessRecordLifecycle

      def initialize(request_recording:, manager_actor: nil, review_note: nil, controller: nil)
        @request_recording = request_recording
        @manager_actor = manager_actor
        @review_note = review_note.to_s.strip.presence
        @controller = controller
      end

      private

      def perform
        validation = validate_request
        return validation unless validation == true

        denied = RecordingStudio::Recording.transaction do
          @request_recording.lock!
          @request_recording.reload
          raise ActiveRecord::Rollback unless pending_snapshot?

          revise_denied!
        end
        return failure(copy("errors.access_request_not_pending")) unless denied

        Hooks.trigger(:access_request_denied, denied)
        success(denied)
      rescue ActiveRecord::RecordInvalid => e
        failure(e.message, errors: e.record.errors.full_messages)
      rescue StandardError => e
        failure(e)
      end

      def validate_request
        return failure(copy("errors.access_request_required")) unless request_recording?
        return failure(copy("errors.access_request_not_pending")) unless pending_snapshot?
        return failure(copy("errors.not_authorized")) unless manager_allowed?
        return failure(copy("errors.review_note_too_long")) if review_note_too_long?

        true
      end

      def revise_denied!
        revised = nil
        AccessRequestCreationContext.allow do
          revised = root_recording.revise(@request_recording, actor: manager) do |request|
            request.status = "denied"
            request.review_note = @review_note
          end
        end
        revised.log_event!(action: RecordingStudio::AccessRequest::EVENT_DENIED, actor: manager)
        revised
      end

      def request_recording?
        @request_recording&.recordable_type == "RecordingStudio::AccessRequest" && target.present?
      end

      def pending_snapshot?
        snapshot&.pending?
      end

      def review_note_too_long?
        @review_note.to_s.length > RecordingStudio::AccessRequest::NOTE_MAX
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
    end
  end
end
