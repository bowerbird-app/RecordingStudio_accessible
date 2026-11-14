# frozen_string_literal: true

module RecordingStudioAccessible
  module AuthorizationClassMethods
    def authorized_recording_ids(actor:, root:, role: :view, recordable_type: nil)
      request = recording_ids_request(actor, root, role, recordable_type)
      return RecordingStudio::Recording.none unless request

      AuthorizedRecordingIds.relation_for(**request)
    end

    private

    def recording_ids_request(actor, root, role, recordable_type)
      return unless present_actor?(actor) && present_recording?(root) && valid_role?(role)
      return unless recordable_type_accepted?(recordable_type)

      {
        actor: actor,
        root: root,
        role: role,
        recordable_type: recordable_type_name_for(recordable_type)
      }
    end

    def present_actor?(actor)
      actor.respond_to?(:id) && actor.id.present?
    end

    def present_recording?(recording)
      recording.is_a?(RecordingStudio::Recording) && recording.id.present?
    end

    def recordable_type_accepted?(recordable_type)
      recordable_type.nil? || recordable_type_name_for(recordable_type).present?
    end

    # Same names recordings_for accepts: a class, or the stored type string.
    def recordable_type_name_for(recordable_type)
      case recordable_type
      when nil
        nil
      when String
        recordable_type.presence
      when Class
        recordable_type.name.presence
      end
    end
  end
end
