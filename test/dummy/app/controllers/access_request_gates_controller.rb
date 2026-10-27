# frozen_string_literal: true

class AccessRequestGatesController < ApplicationController
  helper RecordingStudioAccessible::ApplicationHelper

  skip_before_action :authenticate_user!
  recording_studio_layout { modal_frame? ? false : nil }

  def show
    @recording = gated_recording
    return head(:not_found) unless @recording

    render :show
  end

  def update
    @recording = gated_recording
    return head(:not_found) unless @recording
    return render_blank if params[:why].to_s.strip.blank?

    AccessRequestReasonGate.remember(session, @recording, current_user, params[:why])
    redirect_to return_path
  end

  private

  def gated_recording
    recording = RecordingStudio::Recording.unscoped.find_by(id: params[:recording_id])
    recording if AccessRequestReasonGate.applies?(recording)
  end

  def render_blank
    flash.now[:alert] = "Tell us why you want access."
    render :show, status: :unprocessable_entity
  end

  def return_path
    recording_studio_accessible.new_recording_access_request_path(@recording, **return_options)
  end

  def return_options
    {
      role: params[:role].presence,
      access_action: params[:access_action].presence,
      presentation: ("modal" if params[:presentation].to_s == "modal")
    }.compact
  end

  def modal_frame?
    params[:presentation].to_s == "modal" && request.headers["Turbo-Frame"].to_s == "access_request"
  end

  def gate_form_options
    return { data: { turbo_frame: "access_request" } } if modal_frame?

    { data: { turbo: false } }
  end

  helper_method :modal_frame?, :gate_form_options
end
