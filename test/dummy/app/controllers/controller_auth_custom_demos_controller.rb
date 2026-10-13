# frozen_string_literal: true

# Alternate ControllerAuth wiring for configurable differences (brands-like /
# stripe-like response shapes).
class ControllerAuthCustomDemosController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :set_current_actor
  skip_recording_studio_root_resolution

  include RecordingStudioAccessible::ControllerAuth

  recording_studio_auth(
    config: -> { ControllerAuthDemoConfig },
    prefix: :custom,
    set_current_actor: false,
    actor_resolution: :method_only,
    missing_actor_status: :forbidden,
    missing_root_status: :not_found,
    response_style: :plain,
    plain_bodies: {
      unauthorized: "sign in",
      missing_actor: "no actor",
      forbidden: "no access",
      missing_root: "pick a workspace"
    }
  )

  prepend_before_action :plant_current_actor_from_param, if: -> { params[:plant_actor_email].present? }

  def show
    render plain: [
      "actor=#{custom_actor&.email}",
      "current_actor=#{(defined?(Current) && Current.actor)&.email}"
    ].join(" ")
  end

  def authorize
    recording = RecordingStudio::Recording.unscoped.find(params[:recording_id])
    authorize_recording!(recording, role: params.fetch(:role, "view").to_sym)
    return if performed?

    render plain: "authorized"
  end

  def require_root
    require_root!
    return if performed?

    render plain: "root=#{current_custom_root.id}"
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

  # Test-only authentication that lets the request through with no actor.
  def allow_without_actor!; end
end
