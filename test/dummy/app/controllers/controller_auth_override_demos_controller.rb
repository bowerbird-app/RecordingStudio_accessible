# frozen_string_literal: true

# Proves host overrides on the prefixed one-liners still win.
class ControllerAuthOverrideDemosController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :set_current_actor

  include RecordingStudioAccessible::ControllerAuth

  recording_studio_auth(
    config: -> { ControllerAuthDemoConfig },
    prefix: :override
  )

  def show
    render plain: "actor=#{override_actor&.email}"
  end

  private

  def authenticate_override_actor!
    head :unauthorized unless params[:token].to_s == "demo-token"
  end

  def override_actor
    User.find_by(email: "admin@admin.com")
  end
end
