# frozen_string_literal: true

module RecordingStudioAccessible
  class ActorAccessPointsController < ApplicationController
    include RecordingStudioAccessible::NavigationUrlSafety

    ACTOR_TYPE_PATTERN = /\A[A-Z][A-Za-z0-9_:]{0,120}\z/
    UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
    layout "recording_studio_accessible/blank"

    before_action :load_workspace!
    before_action :load_workspace_root_recording!
    before_action :load_actor!
    before_action :authorize_actor_access_points!
    before_action :load_access_rows

    helper_method :actor_access_points_anchor_url

    def index; end

    private

    def load_workspace!
      head :not_found and return unless defined?(::Workspace)

      return head :not_found unless params[:workspace_id].to_s.match?(UUID_PATTERN)

      @workspace = ::Workspace.find_by(id: params[:workspace_id])
      head :not_found unless @workspace
    rescue ActiveRecord::StatementInvalid, ArgumentError
      head :not_found
    end

    def load_workspace_root_recording!
      @workspace_root_recording = RecordingStudio.root_recording_for(@workspace)
      head :not_found unless @workspace_root_recording
    end

    def load_actor!
      actor_id = params[:actor_id].presence
      actor_type = params[:actor_type].presence
      return head :not_found unless actor_id && actor_type
      return head :not_found unless actor_id.to_s.match?(UUID_PATTERN)

      @actor_id = actor_id
      @resolved_actor_type = permitted_actor_type_for(actor_type)
      head :not_found unless @resolved_actor_type
    end

    def load_access_rows
      access_recordings = workspace_access_recordings.to_a
      return head :not_found if access_recordings.empty?

      @actor = access_recordings.first.recordable.actor
      @actor_label = RecordingStudioAccessible.configuration.actor_label_for(@actor)
      @actor_type_label = @resolved_actor_type.demodulize

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
        .where(recording_studio_accesses: { actor_type: @resolved_actor_type, actor_id: @actor_id })
        .includes(:parent_recording, :recordable)
        .order(created_at: :asc, id: :asc)
    end

    def authorize_actor_access_points!
      return if requested_current_actor?
      return if RecordingStudioAccessible::AccessManagementPolicy.allowed?(
        recording: @workspace_root_recording,
        actor: current_actor,
        controller: self
      )

      head :not_found
    end

    def current_actor = RecordingStudioAccessible.configuration.current_actor_for(controller: self)

    def unauthorized_mounted_page_redirect_path
      (main_app.root_path if respond_to?(:main_app) && main_app.respond_to?(:root_path)) || "/"
    end

    def actor_access_points_anchor_url
      back_url = safe_local_navigation_url(params[:back_url], fallback: unauthorized_mounted_page_redirect_path)

      safe_local_navigation_url(params[:anchor_url], fallback: back_url)
    end

    def permitted_actor_type_for(actor_type)
      return unless valid_actor_type_param?(actor_type)

      configured_types = RecordingStudioAccessible.configuration.access_actor_types
      return unless configured_types.is_a?(Array) && configured_types.present?

      actor_type.to_s if configured_types.include?(actor_type.to_s)
    end

    def valid_actor_type_param?(actor_type)
      actor_type.to_s.match?(ACTOR_TYPE_PATTERN)
    end

    def requested_current_actor?
      actor = current_actor
      return false unless actor

      RecordingStudioAccessible::ActorType.for(actor) == @resolved_actor_type &&
        actor.id.to_s == @actor_id.to_s
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
