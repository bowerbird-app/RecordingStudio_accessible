class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  layout :application_layout

  before_action :authenticate_user!
  before_action :set_current_actor

  helper_method :recording_studio_accessible_docs_visible?

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

    root_recording = RecordingStudio::Recording.unscoped.find_by(recordable: workspace, parent_recording_id: nil)
    return false unless root_recording

    RecordingStudioAccessible.configuration.authorize_mounted_page?(
      controller: self,
      actor: current_user,
      recording: root_recording
    )
  end
end
