# frozen_string_literal: true

class AccessRequestDemosController < ApplicationController
  skip_before_action :authenticate_user!

  def show
    @recording = demo_recording
    head :not_found unless @recording
  end

  private

  def demo_recording
    return RecordingStudio::Recording.unscoped.find(params[:recording_id]) if params[:recording_id].present?

    workspace = Workspace.find_by(name: "Restricted Demo Workspace")
    return unless workspace

    RecordingStudio.root_recording_for(workspace)
  end
end
