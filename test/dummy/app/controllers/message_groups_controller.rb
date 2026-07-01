class MessageGroupsController < ApplicationController
  def index
    @through_workspace = Workspace.find_by(name: "Accessible Demo Workspace")
    @message_groups = message_group_rows
  end

  private

  def message_group_rows
    return [] unless @through_workspace

    MessageGroup.includes(:message_root).order(:position, :name).filter_map do |message_group|
      recording = RecordingStudio::Recording.unscoped.find_by(recordable: message_group)
      next unless recording

      direct_access = RecordingStudioAccessible.authorized?(
        actor: current_user,
        recording: recording,
        role: :view
      )
      through_access = RecordingStudioAccessible.authorized_through?(
        actor: current_user,
        through: @through_workspace,
        recording: recording,
        role: :view,
        controller: self
      )
      next unless through_access

      {
        name: message_group.name,
        summary: message_group.summary,
        root: message_group.message_root.name,
        direct_access: direct_access,
        through_access: through_access,
        role: RecordingStudioAccessible.role_through(
          actor: current_user,
          through: @through_workspace,
          recording: recording,
          controller: self
        )
      }
    end
  end
end
