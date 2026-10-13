# frozen_string_literal: true

# stripe-shaped: no authenticate before_action, require_root! checks actor then root.
class ControllerAuthStripeDemosController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :set_current_actor
  skip_recording_studio_root_resolution

  include RecordingStudioAccessible::ControllerAuth

  recording_studio_auth(
    config: -> { ControllerAuthDemoConfig },
    prefix: :stripe,
    authenticate: false,
    set_current_actor: false,
    require_actor: true,
    actor_resolver: -> { current_user if respond_to?(:current_user, true) },
    root_resolver: lambda {
      next if params[:root_recording_id].blank?

      RecordingStudio::Recording.unscoped.find_by(id: params[:root_recording_id])
    },
    on_missing_actor_for_root: lambda {
      redirect_to new_user_session_path, alert: "sign in"
    },
    missing_root_status: :not_found,
    response_style: :plain,
    plain_bodies: { missing_root: "pick a workspace" }
  )

  before_action :require_root!

  def show
    render plain: "root=#{current_stripe_root.id} actor=#{stripe_actor&.email}"
  end
end
