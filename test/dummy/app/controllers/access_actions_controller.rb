class AccessActionsController < ApplicationController
  def show
    action_name = registered_action_name!

    @action_label = action_label_for(action_name)

    @authorized = RecordingStudioAccessible.authorized_action?(
      actor: current_user,
      action: action_name,
      recording: current_workspace_recording
    )
  end

  private

  def registered_action_name!
    action_name = RecordingStudioAccessible.registered_actions.keys.find do |registered_action|
      registered_action.to_s == params[:action_name].to_s
    end

    action_name || raise(ActiveRecord::RecordNotFound)
  end

  def action_label_for(action_name)
    RecordingStudioAccessible.action_registration_for(action_name)&.fetch(:label) || action_name.to_s.humanize
  end
end
