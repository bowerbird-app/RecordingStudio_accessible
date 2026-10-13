# frozen_string_literal: true

# Dummy host controller that exercises RecordingStudioAccessible::ControllerAuth
# the way sibling addon ApplicationControllers will.
class ControllerAuthDemosController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :set_current_actor
  skip_recording_studio_root_resolution

  include RecordingStudioAccessible::ControllerAuth

  recording_studio_auth(
    config: -> { ControllerAuthDemoConfig },
    prefix: :demo
  )

  # Test-only: plant Current.actor before the concern resolves the actor.
  prepend_before_action :plant_current_actor_from_param, if: -> { params[:plant_actor_email].present? }
  prepend_before_action :plant_blank_current_actor, if: -> { params[:plant_blank_current_actor].present? }

  def show
    render plain: [
      "actor=#{demo_actor&.email}",
      "current_actor=#{Current.actor&.email}",
      "root=#{current_demo_root&.id}"
    ].join(" ")
  end

  def authorize
    recording = RecordingStudio::Recording.unscoped.find(params[:recording_id])
    authorize_recording!(recording, role: params.fetch(:role, "view").to_sym)
    return if performed?

    render plain: "authorized"
  end

  def authorize_nil_recording
    authorize_recording!(nil, role: :view)
    return if performed?

    render plain: "authorized"
  end

  def require_root
    require_root!
    return if performed?

    render plain: "root=#{current_demo_root.id}"
  end

  # Public like RootSwitchable::ControllerSupport — ControllerAuth uses respond_to? without true.
  def current_root_recording
    return if params[:root_recording_id].blank?

    RecordingStudio::Recording.unscoped.find_by(id: params[:root_recording_id])
  end

  private

  def plant_current_actor_from_param
    Current.actor = User.find_by!(email: params[:plant_actor_email])
  end

  def plant_blank_current_actor
    Current.actor = ""
  end

  # Test-only authentication that lets the request through with no actor.
  def allow_without_actor!; end
end
