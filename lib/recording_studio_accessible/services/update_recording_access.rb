# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class UpdateRecordingAccess < BaseService
      def initialize(recording:, access_recording:, role:, manager_actor: nil)
        @recording = recording
        @access_recording = access_recording
        @role = role.to_s
        @manager_actor = manager_actor
      end

      private

      def perform
        return failure("Recording is required") unless @recording
        return failure("Access recording is required") unless @access_recording
        return failure("Access recording is invalid") unless valid_access_recording?
        return failure("Role is invalid") unless valid_role?

        ensure_current_impersonator_accessor!

        revised_recording = @access_recording.root_recording.revise(@access_recording, actor: @manager_actor) do |access|
          access.role = @role
        end

        success(revised_recording)
      rescue ActiveRecord::RecordInvalid => e
        failure(e.message, errors: e.record.errors.full_messages)
      rescue StandardError => e
        failure(e)
      end

      def service_args
        {
          recording_id: @recording&.id,
          access_recording_id: @access_recording&.id,
          role: @role,
          manager_actor_gid: @manager_actor&.to_global_id&.to_s
        }
      end

      def valid_access_recording?
        @access_recording.parent_recording_id == @recording.id &&
          @access_recording.recordable_type == "RecordingStudio::Access"
      end

      def valid_role?
        RecordingStudio::Access.roles.key?(@role)
      end

      def ensure_current_impersonator_accessor!
        return unless defined?(Current)
        return unless Current.respond_to?(:attribute)
        return if Current.respond_to?(:impersonator)

        Current.attribute :impersonator
      end
    end
  end
end