# frozen_string_literal: true

module RecordingStudioAccessible
  class RecordingAccessBoundariesController < ApplicationController
    DEFAULT_MINIMUM_ROLE = "edit"

    layout "recording_studio_accessible/blank"

    before_action :set_recording
    before_action :ensure_boundary_children_enabled!
    before_action :authorize_access_management!
    before_action :prepare_page_state
    before_action :set_boundary_recording, only: [:destroy]

    def new; end

    def create
      result = RecordingStudioAccessible::Services::CreateRecordingAccessBoundary.call(
        recording: @recording,
        minimum_role: DEFAULT_MINIMUM_ROLE,
        manager_actor: current_actor
      )

      if result.success?
        redirect_to recording_accesses_path(@recording), notice: "Boundary added."
      else
        flash.now[:alert] = result.errors.presence || result.error
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      result = RecordingStudioAccessible::Services::RemoveRecordingAccessBoundary.call(
        recording: @recording,
        boundary_recording: @boundary_recording,
        manager_actor: current_actor
      )

      if result.success?
        redirect_to recording_accesses_path(@recording), notice: "Boundary removed."
      else
        redirect_to recording_accesses_path(@recording), alert: result.errors.presence || result.error
      end
    end

    private

    def set_recording
      @recording = RecordingStudio::Recording.unscoped.find(params[:recording_id])
    end

    def ensure_boundary_children_enabled!
      return if RecordingStudioAccessible::PlacementPolicy.allowed_child_on_recording?(recording: @recording,
                                                                                       child_type: :boundary)

      head :not_found
    end

    def authorize_access_management!
      return if RecordingStudioAccessible::AccessManagementPolicy.allowed?(
        recording: @recording,
        actor: current_actor,
        controller: self
      )

      head :forbidden
    end

    def prepare_page_state
      @recording_label = RecordingStudio::Labels.title_for(@recording.recordable)
    end

    def set_boundary_recording
      @boundary_recording = RecordingStudio::Recording.unscoped.find_by(
        parent_recording_id: @recording.id,
        recordable_type: "RecordingStudio::AccessBoundary",
        trashed_at: nil
      )

      head :not_found unless @boundary_recording
    end

    def current_actor
      RecordingStudioAccessible.configuration.current_actor_for(controller: self)
    end
  end
end