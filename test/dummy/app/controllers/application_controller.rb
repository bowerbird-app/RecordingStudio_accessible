class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  layout :application_layout

  before_action :authenticate_user!
  before_action :set_current_actor

  helper_method :recording_studio_accessible_docs_visible?
  helper_method :recording_studio_accessible_my_access_url
  helper_method :recording_studio_accessible_my_access_visible?

  private

  def application_layout
    devise_controller? ? "application" : "flat_pack_sidebar"
  end

  def set_current_actor
    Current.actor = current_user
  end

  def recording_studio_accessible_docs_visible?
    return false unless user_signed_in?
    return false unless defined?(Workspace)
    return false unless defined?(RecordingStudio::Recording)

    workspace = Workspace.order(:name, :id).first
    return false unless workspace

    root_recording = RecordingStudio.root_recording_for(workspace)
    return false unless root_recording

    RecordingStudioAccessible.configuration.authorize_mounted_page?(
      controller: self,
      actor: current_user,
      recording: root_recording
    )
  end

  def recording_studio_accessible_my_access_visible?
    recording_studio_accessible_docs_visible?
  end

  def recording_studio_accessible_my_access_url
    return unless recording_studio_accessible_my_access_visible?

    workspace = Workspace.order(:name, :id).first
    return unless workspace

    anchor = request&.fullpath.presence || "/"

    recording_studio_accessible.workspace_actor_access_points_path(
      workspace_id: workspace.id,
      actor_type: current_user.class.base_class.name,
      actor_id: current_user.id,
      back_url: anchor,
      anchor_url: anchor
    )
  end
end
