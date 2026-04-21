class HomeController < ApplicationController
  def index
    @workspace = Workspace.first
    @root_recording = RecordingStudio::Recording.unscoped.find_by(recordable: @workspace, parent_recording_id: nil)
    @integration_mode = RecordingStudioAccessible::Compatibility.integration_mode
    @viewer_user = User.find_by(email: "viewer@admin.com")
    @access_rows = build_access_rows
  end

  private

  def build_access_rows
    return [] unless @root_recording

    [
      access_row(label: current_user.email, actor: current_user, minimum_role: :admin),
      access_row(label: @viewer_user&.email || "viewer@admin.com", actor: @viewer_user, minimum_role: :view),
      access_row(label: "Anonymous", actor: nil, minimum_role: :view)
    ]
  end

  def access_row(label:, actor:, minimum_role:)
    {
      label: label,
      role: RecordingStudio::Services::AccessCheck.role_for(actor: actor, recording: @root_recording),
      allowed: RecordingStudio::Services::AccessCheck.allowed?(actor: actor, recording: @root_recording, role: minimum_role)
    }
  end
end
