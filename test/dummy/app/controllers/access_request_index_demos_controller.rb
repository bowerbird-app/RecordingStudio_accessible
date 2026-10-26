# frozen_string_literal: true

class AccessRequestIndexDemosController < ApplicationController
  recording_studio_layout { nil }

  def show
    @recordings = RecordingStudio::Recording.unscoped.where(id: params[:recording_ids].to_s.split(","))
    @list_url = access_request_index_demo_path(recording_ids: params[:recording_ids])
  end
end
