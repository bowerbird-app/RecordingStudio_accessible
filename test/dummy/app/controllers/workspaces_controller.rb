class WorkspacesController < ApplicationController
  def show
    @workspace = Workspace.includes(folders: { pages: :cards }).find(params[:id])
  end

  def create
    name = workspace_name
    if name.blank?
      redirect_to root_path, alert: "Give this workspace a name first."
      return
    end

    workspace = Workspace.create!(name: name)
    root = RecordingStudio.root_recording_for(workspace)
    result = RecordingStudioAccessible.bootstrap_owner_access!(
      recording: root,
      actor: current_user
    )

    unless result.success?
      redirect_to root_path, alert: "Couldn’t make you the first owner. #{result.error}"
      return
    end

    RecordingStudio::RootSwitchable.switch_root(
      root_recording_id: root.id,
      scope_key: "workspaces",
      controller: self,
      actor: current_user,
      device_key: current_root_device_key
    )

    redirect_to root_path, notice: "You’re in. #{workspace.name} is yours — invite people next."
  end

  private

  def workspace_name
    params.dig(:workspace, :name).to_s.strip
  end
end
