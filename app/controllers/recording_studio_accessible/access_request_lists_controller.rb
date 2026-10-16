# frozen_string_literal: true

module RecordingStudioAccessible
  class AccessRequestListsController < ApplicationController
    helper AccessRequestsHelper
    layout "recording_studio_accessible/blank"

    def index
      return head :forbidden if current_actor.blank?

      @list_url = access_requests_path
      @page = index_page
      render "recording_studio_accessible/access_requests/index"
    end

    private

    def index_page
      AccessRequestIndex.page(
        recordings: index_recordings, actor: current_actor, controller: self,
        status: params[:status], cursor: params[:cursor]
      )
    end

    def index_recordings
      configured = RecordingStudioAccessible.configuration.access_request_index_recordings_for(
        actor: current_actor, controller: self
      )
      return configured unless configured.nil?

      AccessRequestQuery.parent_recordings
    end

    def current_actor
      RecordingStudioAccessible.configuration.current_actor_for(controller: self)
    end
  end
end
