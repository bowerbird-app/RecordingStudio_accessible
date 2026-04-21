class HomeController < ApplicationController
  def index
    @workspace = Workspace.includes(folders: { pages: :cards }).order(:name).first
    @root_recording = root_recording_for(@workspace)
    @demo_sections = build_demo_sections
    @demo_users = load_demo_users
    @access_matrix = build_access_matrix
  end

  private

  def load_demo_users
    User.where(email: demo_user_emails).order(:email)
  end

  def demo_user_emails
    %w[
      admin@admin.com
      editor@admin.com
      outsider@admin.com
      page_owner@admin.com
      viewer@admin.com
    ]
  end

  def build_demo_sections
    return [] unless @workspace

    @workspace.folders.map do |folder|
      folder_recording = recording_for(folder)

      {
        folder: folder,
        folder_recording: folder_recording,
        pages: folder.pages.order(:position, :title).map do |page|
          {
            page: page,
            page_recording: recording_for(page),
            cards: page.cards.order(:position, :title)
          }
        end
      }
    end
  end

  def build_access_matrix
    return [] unless @root_recording

    resources = [{ label: @workspace.name, recording: @root_recording }]
    @demo_sections.each do |section|
      resources << { label: section[:folder].name, recording: section[:folder_recording] }
      section[:pages].each do |page_section|
        resources << { label: page_section[:page].title, recording: page_section[:page_recording] }
      end
    end

    @demo_users.map do |user|
      {
        user: user,
        resources: resources.map { |resource| access_row(user: user, **resource) }
      }
    end
  end

  def access_row(user:, label:, recording:)
    {
      label: label,
      role: role_for(user, recording),
      allowed: allowed_to_view?(user, recording)
    }
  end

  def role_for(user, recording)
    return nil unless recording

    RecordingStudio::Services::AccessCheck.role_for(actor: user, recording: recording)
  end

  def allowed_to_view?(user, recording)
    return false unless recording

    RecordingStudio::Services::AccessCheck.allowed?(actor: user, recording: recording, role: :view)
  end

  def root_recording_for(recordable)
    return unless recordable

    RecordingStudio::Recording.unscoped.find_by(recordable: recordable, parent_recording_id: nil)
  end

  def recording_for(recordable)
    return unless recordable

    RecordingStudio::Recording.unscoped.find_by(recordable: recordable)
  end
end
