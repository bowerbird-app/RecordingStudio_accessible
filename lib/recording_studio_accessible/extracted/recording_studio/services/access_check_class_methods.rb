# frozen_string_literal: true

module RecordingStudio
  module Services
    module AccessCheckClassMethods
      def role_for(actor:, recording:)
        return nil unless actor

        call(actor: actor, recording: recording).value
      end

      def allowed?(actor:, recording:, role:)
        return false unless actor

        call(actor: actor, recording: recording, role: role).value
      end

      def root_recordings_for(actor:, minimum_role: nil)
        return [] unless actor

        root_access_recordings_for(actor: actor, minimum_role: minimum_role)
          .distinct
          .pluck(:root_recording_id)
      end

      def root_recording_ids_for(actor:, minimum_role: nil)
        return [] unless actor

        root_access_recordings_for(actor: actor, minimum_role: minimum_role)
          .distinct
          .pluck(:root_recording_id)
      end

      def access_recordings_for(recording)
        RecordingStudio::Recording.unscoped
                                  .where(parent_recording_id: recording.id)
                                  .where(recordable_type: "RecordingStudio::Access")
                                  .where(trashed_at: nil)
      end

      private

      def root_access_recordings_for(actor:, minimum_role:)
        access_scope = access_scope_for(actor: actor, minimum_role: minimum_role)
        return RecordingStudio::Recording.none unless access_scope

        root_ids = RecordingStudio::Recording.unscoped.where(parent_recording_id: nil).select(:id)
        RecordingStudio::Recording.unscoped
                                  .where(recordable_type: "RecordingStudio::Access")
                                  .where(parent_recording_id: root_ids)
                                  .where(trashed_at: nil)
                                  .where(recordable_id: access_scope.select(:id))
      end

      def access_scope_for(actor:, minimum_role:)
        scope = RecordingStudio::Access.where(actor_type: actor.class.name, actor_id: actor.id)
        return scope if minimum_role.blank?

        minimum_value = RecordingStudio::Access.roles[minimum_role.to_s]
        return nil unless minimum_value

        scope.where(role: minimum_value..)
      end
    end
  end
end
