class WorkspacesController < ApplicationController
  def show
    @workspace = Workspace.includes(folders: { pages: :cards }).find(params[:id])
  end
end
