# frozen_string_literal: true

module RecordingStudioAccessible
  class SharedWithController < ApplicationController
    helper SharedWithHelper

    def index
      return head :forbidden if current_actor.blank?

      @list_url = shared_with_path
      @page = RecordingStudioAccessible.shared_with(actor: current_actor, cursor: params[:cursor])
    rescue SharedWith::InvalidCursor
      head :bad_request
    end

    private

    def current_actor
      RecordingStudioAccessible.configuration.current_actor_for(controller: self)
    end
  end
end
