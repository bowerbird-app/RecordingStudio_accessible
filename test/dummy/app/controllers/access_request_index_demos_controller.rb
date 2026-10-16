# frozen_string_literal: true

class AccessRequestIndexDemosController < ApplicationController
  layout "recording_studio_accessible/blank"

  def show
    @recordings = RecordingStudio::Recording.unscoped.where(id: params[:recording_ids].to_s.split(","))
    @list_url = access_request_index_demo_path(recording_ids: params[:recording_ids])
  end
end
