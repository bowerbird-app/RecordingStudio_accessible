# frozen_string_literal: true

module RecordingStudioAccessible
  class ActorAccessPointsController < ApplicationController
    layout "recording_studio_accessible/blank"

    before_action :load_workspace!
    before_action :load_workspace_root_recording!
    before_action :authorize_mounted_page!
    before_action :load_actor!
    before_action :load_access_rows

    helper_method :actor_access_points_anchor_url

    def index; end

    private

    def load_workspace!
      head :not_found and return unless defined?(::Workspace)

      @workspace = ::Workspace.find_by(id: params[:workspace_id])
      head :not_found unless @workspace
    end

    def load_workspace_root_recording!
      @workspace_root_recording = RecordingStudio.root_recording_for(@workspace)
      head :not_found unless @workspace_root_recording
    end

    def load_actor!
      actor_id = params[:actor_id].presence
      actor_type = params[:actor_type].presence
      return head :not_found unless actor_id && actor_type
      return head :not_found unless allowed_actor_type_param?(actor_type)

      actor_class = actor_type.safe_constantize
      return head :not_found unless actor_class.respond_to?(:find_by)

      @actor = actor_class.find_by(id: actor_id)
      head :not_found unless @actor
      @resolved_actor_type = RecordingStudioAccessible::ActorType.for(@actor)
    end

    def load_access_rows
      access_recordings = workspace_access_recordings.to_a
      return head :not_found if access_recordings.empty?

      @actor_label = RecordingStudioAccessible.configuration.actor_label_for(@actor)
      @actor_type_label = @actor.class.name.demodulize

      @access_rows = access_recordings.map do |access_recording|
        {
          access_point: recordable_label_for(access_recording.parent_recording&.recordable),
          role: access_recording.recordable.role,
          recording_id: access_recording.id
        }
      end
    end

    def workspace_access_recordings
      scope = RecordingStudio::Recording.unscoped
      scope = scope.where(trashed_at: nil) if RecordingStudio::Recording.column_names.include?("trashed_at")

      scope
        .where(root_recording_id: @workspace_root_recording.id, recordable_type: "RecordingStudio::Access")
        .joins(RecordingStudioAccessible::DirectAccessQuery::ACCESS_JOIN_SQL)
        .where(recording_studio_accesses: { actor_type: @resolved_actor_type, actor_id: @actor.id })
        .includes(:parent_recording, :recordable)
        .order(created_at: :asc, id: :asc)
    end

    def authorize_mounted_page!
      return if RecordingStudioAccessible.configuration.authorize_mounted_page?(
        controller: self,
        actor: current_actor,
        recording: @workspace_root_recording
      )

      redirect_to unauthorized_mounted_page_redirect_path
    end

    def current_actor
      RecordingStudioAccessible.configuration.current_actor_for(controller: self)
    end

    def unauthorized_mounted_page_redirect_path
      return main_app.root_path if respond_to?(:main_app) && main_app.respond_to?(:root_path)

      "/"
    end

    def actor_access_points_anchor_url
      params[:anchor_url].presence || params[:back_url].presence || unauthorized_mounted_page_redirect_path
    end

    def allowed_actor_type_param?(actor_type)
      configured_types = RecordingStudioAccessible.configuration.access_actor_types
      return true if configured_types.blank?

      configured_types.include?(actor_type.to_s)
    end

    def recordable_label_for(recordable)
      return "Unknown" unless recordable
      return recordable.recordable_name if recordable.respond_to?(:recordable_name)
      return recordable.name if recordable.respond_to?(:name)
      return recordable.title if recordable.respond_to?(:title)

      recordable.class.name.demodulize
    end
  end
end
