class HomeController < ApplicationController
  def index
    @workspace = Workspace.includes(folders: { pages: :cards }).order(:name).first
    @root_recording = root_recording_for(@workspace)
    @root_access_management_enabled = access_management_enabled_for(@root_recording)
    @demo_sections = build_demo_sections
    @demo_users = load_demo_users
    @access_matrix = build_access_matrix
    @workspace_access_rows = build_workspace_access_rows
    @access_rows_by_label = build_access_rows_by_label
    @direct_access_counts_by_recording_id = build_direct_access_counts_by_recording_id
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
        folder_access_management_enabled: access_management_enabled_for(folder_recording),
        pages: folder.pages.order(:position, :title).map do |page|
          page_recording = recording_for(page)

          {
            page: page,
            page_recording: page_recording,
            page_access_management_enabled: access_management_enabled_for(page_recording),
            cards: page.cards.order(:position, :title)
          }
        end
      }
    end
  end

  def build_access_matrix
    return [] unless @root_recording

    resources = [ { label: @workspace.name, recording: @root_recording } ]
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

  def build_workspace_access_rows
    return [] unless @workspace

    @access_matrix.filter_map do |row|
      workspace_access = row[:resources].find { |resource| resource[:label] == @workspace.name }
      next unless workspace_access&.dig(:allowed)

      {
        user: row[:user],
        email: row[:user].email,
        role: workspace_access[:role]
      }
    end
  end

  def build_access_rows_by_label
    @access_matrix.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |row, grouped_rows|
      row[:resources].each do |resource|
        next unless resource[:allowed]

        grouped_rows[resource[:label]] << {
          user: row[:user],
          email: row[:user].email,
          role: resource[:role]
        }
      end
    end
  end

  def build_direct_access_counts_by_recording_id
    recordings = @demo_sections.flat_map do |section|
      [ section[:folder_recording], *section[:pages].map { |page_section| page_section[:page_recording] } ]
    end.compact

    recordings.each_with_object({}) do |recording, counts|
      actor_keys = RecordingStudio::Services::AccessCheck.access_recordings_for(recording).filter_map do |access_recording|
        actor = access_recording.recordable.actor
        next unless actor

        [ actor.class.base_class.name, actor.id ]
      end

      counts[recording.id] = actor_keys.uniq.count
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

  def access_management_enabled_for(recording)
    RecordingStudioAccessible::PlacementPolicy.allowed_child_on_recording?(recording: recording, child_type: :access)
  end
end
