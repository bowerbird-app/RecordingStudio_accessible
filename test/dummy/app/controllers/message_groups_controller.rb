class MessageGroupsController < ApplicationController
  def index
    @through_workspace = demo_through_workspace
    @message_groups = visible_message_group_rows_for(current_user)
  end
end
