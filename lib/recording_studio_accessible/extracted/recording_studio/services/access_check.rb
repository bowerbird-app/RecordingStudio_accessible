# frozen_string_literal: true

module RecordingStudio
  module Services
    class AccessCheck < RecordingStudio::Services::BaseService
      extend AccessCheckClassMethods

      ROLE_ORDER = { "view" => 0, "edit" => 1, "admin" => 2 }.freeze

      def initialize(actor:, recording:, role: nil)
        super()
        @actor = actor
        @recording = recording
        @role = role&.to_s
      end

      private

      def perform
        return success(false) if @actor.nil? && @role
        return success(nil) if @actor.nil?

        resolved = resolve_role
        return success(role_satisfies_requirement?(resolved)) if @role

        success(resolved&.to_sym)
      end

      def role_satisfies_requirement?(resolved)
        required_role_value = ROLE_ORDER[@role]
        return false unless required_role_value

        resolved.present? && ROLE_ORDER.fetch(resolved, -1) >= required_role_value
      end

      def resolve_role
        path, boundary = recording_path_and_boundary
        role = find_access_on_path(path)
        return role if role

        return find_root_access unless boundary

        resolve_role_with_boundary(boundary)
      end

      def boundary_parent_ids
        @boundary_parent_ids ||= begin
          root_id = @recording.root_recording_id || @recording.id
          RecordingStudio::Recording.unscoped
                                    .where(root_recording_id: root_id,
                                           recordable_type: "RecordingStudio::AccessBoundary",
                                           trashed_at: nil)
                                    .pluck(:parent_recording_id)
                                    .to_set
        end
      end

      def boundary_child?(recording)
        boundary_parent_ids.include?(recording.id)
      end

      def find_boundary_recordable_for(recording)
        RecordingStudio::Recording.unscoped
                                  .where(parent_recording_id: recording.id,
                                         recordable_type: "RecordingStudio::AccessBoundary",
                                         trashed_at: nil)
                                  .order(created_at: :desc, id: :desc)
                                  .first&.recordable
      end

      def find_access_on_path(path)
        path.each do |rec|
          role = find_access_for_recording(rec)
          return role if role
        end
        nil
      end

      def find_access_above(boundary_parent)
        current = boundary_parent.parent_recording
        while current
          role = find_access_for_recording(current)
          return role if role

          break if boundary_child?(current)

          current = current.parent_recording
        end
        nil
      end

      def find_access_for_recording(recording)
        access = self.class.access_recordings_for_actor(recording: recording, actor: @actor).first
        access&.recordable&.role
      end

      def find_root_access
        root = @recording.root_recording || @recording
        return nil unless root

        self.class.access_recordings_for_actor(recording: root, actor: @actor)
            .where(root_recording_id: root.id)
            .first&.recordable&.role
      end

      def recording_path_and_boundary
        path = []
        current = @recording

        current = collect_non_boundary_path(path, current)
        [path, current]
      end

      def collect_non_boundary_path(path, current)
        while current
          boundary_here = boundary_child?(current)
          path << current unless boundary_here && current.parent_recording_id.nil?
          break if boundary_here

          current = current.parent_recording
        end
        current
      end

      def resolve_role_with_boundary(boundary_parent)
        boundary_recordable = find_boundary_recordable_for(boundary_parent)
        minimum_role = boundary_recordable&.minimum_role
        return nil if minimum_role.blank?

        inherited_role = find_access_above(boundary_parent) || find_root_access
        return nil unless inherited_role

        required_value = ROLE_ORDER.fetch(minimum_role, -1)
        role_value = ROLE_ORDER.fetch(inherited_role, -1)
        role_value >= required_value ? inherited_role : nil
      end
    end
  end
end
