# frozen_string_literal: true

# site_settings-shaped names + configured_as_is actor resolution.
class ControllerAuthSiteSettingsDemosController < ApplicationController
  skip_before_action :authenticate_user!
  skip_before_action :set_current_actor
  skip_recording_studio_root_resolution

  include RecordingStudioAccessible::ControllerAuth

  recording_studio_auth(
    config: -> { ControllerAuthDemoConfig },
    prefix: :site_settings,
    authenticate_method: :authenticate_recording_studio_site_settings!,
    set_current_actor_method: :set_current_actor,
    actor_method: :current_actor,
    actor_resolution: :configured_as_is
  )

  def show
    render plain: [
      "actor=#{current_actor&.email}",
      "current_actor=#{Current.actor&.email}"
    ].join(" ")
  end

  private

  def allow_without_actor!; end
end
