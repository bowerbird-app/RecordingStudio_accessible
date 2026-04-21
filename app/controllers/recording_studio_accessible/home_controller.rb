# frozen_string_literal: true

module RecordingStudioAccessible
  class HomeController < ApplicationController
    def index
      @integration_mode = RecordingStudioAccessible::Compatibility.integration_mode
      @workspace = defined?(::Workspace) ? ::Workspace.first : nil
      @root_recording = find_root_recording
      @admin_user = resolve_admin_user
      @viewer_user = resolve_viewer_user
      @access_rows = build_access_rows
    end

    private

    def find_root_recording
      return unless @workspace && defined?(::RecordingStudio::Recording)

      RecordingStudio::Recording.unscoped.find_by(recordable: @workspace, parent_recording_id: nil)
    end

    def resolve_admin_user
      return current_user if respond_to?(:current_user) && current_user.present?
      return unless defined?(::User)

      ::User.find_by(email: "admin@admin.com") || ::User.first
    end

    def resolve_viewer_user
      return unless defined?(::User)

      ::User.where.not(id: @admin_user&.id).order(:email).first
    end

    def build_access_rows
      return [] unless @root_recording && defined?(::RecordingStudio::Services::AccessCheck)

      [
        access_row(label: @admin_user&.email || "Admin", actor: @admin_user, minimum_role: :admin),
        access_row(label: @viewer_user&.email || "Viewer", actor: @viewer_user, minimum_role: :view),
        access_row(label: "Anonymous", actor: nil, minimum_role: :view)
      ]
    end

    def access_row(label:, actor:, minimum_role:)
      {
        label: label,
        role: RecordingStudio::Services::AccessCheck.role_for(actor: actor, recording: @root_recording),
        allowed: RecordingStudio::Services::AccessCheck.allowed?(actor: actor, recording: @root_recording,
                                                                 role: minimum_role)
      }
    end
  end
end
