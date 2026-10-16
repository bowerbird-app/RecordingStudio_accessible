# frozen_string_literal: true

module RecordingStudioAccessible
  module AccessRequestQuery
    TYPE = "RecordingStudio::AccessRequest"
    JOIN_SQL = <<~SQL.squish.freeze
      INNER JOIN recording_studio_access_requests
        ON recording_studio_access_requests.id = recording_studio_recordings.recordable_id
    SQL

    class << self
      def for_parent(recording)
        return RecordingStudio::Recording.none if recording.blank?

        for_parents([recording.id])
      end

      def for_parents(parent_ids)
        return RecordingStudio::Recording.none if Array(parent_ids).empty?

        request_recordings.where(parent_recording_id: parent_ids)
      end

      def parent_recordings
        ids = active_recordings.where(recordable_type: TYPE).distinct.pluck(:parent_recording_id)
        RecordingStudio::Recording.unscoped.where(id: ids)
      end

      def pending_for(recording:, actor:)
        return RecordingStudio::Recording.none unless recording && actor

        for_parent(recording)
          .where(recording_studio_access_requests: { status: "pending" }.merge(actor_filter(actor)))
      end

      def visible?(request_recording:, actor:, controller: nil)
        return false unless access_request_recording?(request_recording)

        manager_visible?(request_recording, actor, controller) || requester_visible?(request_recording, actor)
      end

      private

      def access_request_recording?(request_recording)
        request_recording.present? && request_recording.recordable_type == TYPE
      end

      def manager_visible?(request_recording, actor, controller)
        AccessManagementPolicy.allowed?(
          recording: request_recording.parent_recording, actor: actor, controller: controller
        )
      end

      def requester_visible?(request_recording, actor)
        owner = request_recording.recordable&.actor
        return false unless owner && actor
        return false unless owner.respond_to?(:id) && actor.respond_to?(:id)

        ActorType.for(owner) == ActorType.for(actor) && owner.id == actor.id
      end

      def request_recordings
        active_recordings.where(recordable_type: TYPE).joins(JOIN_SQL).order(order_sql)
      end

      def order_sql
        "recording_studio_recordings.created_at DESC, recording_studio_recordings.id DESC"
      end

      def active_recordings
        scope = RecordingStudio::Recording.unscoped
        return scope unless RecordingStudio::Recording.column_names.include?("trashed_at")

        scope.where(RecordingStudio::Recording.recording_studio_trashable_kept_sql)
      end

      def actor_filter(actor)
        { actor_type: RecordingStudioAccessible::ActorType.for(actor), actor_id: actor.id }
      end
    end
  end
end
