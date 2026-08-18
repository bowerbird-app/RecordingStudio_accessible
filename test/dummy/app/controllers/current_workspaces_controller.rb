# frozen_string_literal: true

class CurrentWorkspacesController < ApplicationController
  def update
    recording = available_workspace_recordings.find { |candidate| candidate.id.to_s == params[:root_recording_id].to_s }
    session[:current_workspace_recording_id] = recording&.id

    redirect_to safe_return_path
  end

  private

  def safe_return_path
    path = params[:return_to].to_s
    return root_path unless path.start_with?("/") && !path.start_with?("//")

    path
  end
end
