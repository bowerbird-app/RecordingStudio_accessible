# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    class GrantRecordingAccess < BaseService
      ACCESS_JOIN_SQL = <<~SQL.squish.freeze
        INNER JOIN recording_studio_accesses
          ON recording_studio_accesses.id = recording_studio_recordings.recordable_id
      SQL

      def initialize(recording:, actor:, role:, manager_actor: nil)
        @recording = recording
        @actor = actor
        @role = role.to_s
        @manager_actor = manager_actor
      end

      private

      def perform
        return failure("Recording is required") unless @recording
        return failure("Actor is required") unless @actor
        return failure("Role is invalid") unless valid_role?

        access_recording = nil
        ensure_current_impersonator_accessor!

        RecordingStudio::Access.transaction do
          access_recording = existing_access_recording

          if access_recording
            root_recording.revise(access_recording, actor: @manager_actor) do |access|
              access.role = @role
            end
          else
            access_recording = root_recording.record(
              RecordingStudio::Access,
              actor: @manager_actor,
              parent_recording: @recording
            ) do |access|
              access.actor = @actor
              access.role = @role
            end
          end
        end

        success(access_recording)
      rescue ActiveRecord::RecordInvalid => e
        failure(e.message, errors: e.record.errors.full_messages)
      rescue StandardError => e
        failure(e)
      end

      def service_args
        {
          recording_id: @recording&.id,
          actor_gid: @actor&.to_global_id&.to_s,
          role: @role,
          manager_actor_gid: @manager_actor&.to_global_id&.to_s
        }
      end

      def valid_role?
        RecordingStudio::Access.roles.key?(@role)
      end

      def root_recording
        @recording.root_recording || @recording
      end

      def ensure_current_impersonator_accessor!
        return unless defined?(Current)
        return unless Current.respond_to?(:attribute)
        return if Current.respond_to?(:impersonator)

        Current.attribute :impersonator
      end

      def existing_access_recording
        RecordingStudio::Services::AccessCheck.access_recordings_for(@recording)
                                              .joins(ACCESS_JOIN_SQL)
                                              .where(recording_studio_accesses: {
                                                       actor_type: @actor.class.name,
                                                       actor_id: @actor.id
                                                     })
                                              .order(created_at: :desc, id: :desc)
                                              .first
      end
    end
  end
end
