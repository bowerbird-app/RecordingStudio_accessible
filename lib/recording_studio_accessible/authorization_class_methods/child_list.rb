# frozen_string_literal: true

require_relative "child_list_request"

module RecordingStudioAccessible
  module AuthorizationClassMethods
    def recordings_for(actor:, parent_recording:, minimum_role: nil, recordable_type: nil)
      request = ChildListRequest.parse(
        actor: actor,
        parent_recording: parent_recording,
        minimum_role: minimum_role,
        recordable_type: recordable_type
      )
      return RecordingStudio::Recording.none unless request

      candidates = direct_child_candidates(request)
      pin_membership(candidates, allowed_child_ids(candidates, request))
    end

    def recording_ids_for(actor:, parent_recording:, minimum_role: nil, recordable_type: nil)
      recordings_for(
        actor: actor,
        parent_recording: parent_recording,
        minimum_role: minimum_role,
        recordable_type: recordable_type
      ).pluck(:id)
    end

    private

    def pin_membership(candidates, ids_at_call)
      candidates.where(id: ids_at_call)
    end

    def direct_child_candidates(request)
      scope = active_recordings_scope.where(parent_recording_id: request.parent_recording.id)
      return scope if request.recordable_type_name.nil?

      scope.where(recordable_type: request.recordable_type_name)
    end

    def allowed_child_ids(candidates, request)
      candidates.filter_map do |child|
        resolved_role = RecordingStudio::Services::AccessResolver.new(
          actor: request.actor,
          recording: child
        ).resolve_role
        child.id if request.floor.keep?(resolved_role)
      end
    end
  end
end
