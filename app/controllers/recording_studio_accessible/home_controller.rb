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

    def overview; end

    def access_methods
      @method_sections = [
        {
          title: "Grant access with RecordingStudio::Access.create!",
          code: <<~RUBY.strip
            access = RecordingStudio::Access.create!(actor: user, role: :view)
          RUBY
        },
        {
          title: "Attach a grant to a recording",
          code: <<~RUBY.strip
            RecordingStudio::Recording.create!(
              root_recording: root_recording,
              recordable: access,
              parent_recording: root_recording
            )
          RUBY
        },
        {
          title: "Create an inheritance cutoff with RecordingStudio::AccessBoundary.create!",
          code: <<~RUBY.strip
            boundary = RecordingStudio::AccessBoundary.create!(minimum_role: :edit)
          RUBY
        },
        {
          title: "Resolve a user's role with RecordingStudio::Services::AccessCheck.role_for",
          code: <<~RUBY.strip
            RecordingStudio::Services::AccessCheck.role_for(
              actor: user,
              recording: recording
            )
          RUBY
        },
        {
          title: "Check authorization with RecordingStudio::Services::AccessCheck.allowed?",
          code: <<~RUBY.strip
            RecordingStudio::Services::AccessCheck.allowed?(
              actor: user,
              recording: recording,
              role: :edit
            )
          RUBY
        },
        {
          title: "List accessible roots with RecordingStudio::Services::AccessCheck.root_recordings_for",
          code: <<~RUBY.strip
            RecordingStudio::Services::AccessCheck.root_recordings_for(
              actor: user,
              minimum_role: :view
            )
          RUBY
        },
        {
          title: "List accessible root ids with RecordingStudio::Services::AccessCheck.root_recording_ids_for",
          code: <<~RUBY.strip
            RecordingStudio::Services::AccessCheck.root_recording_ids_for(
              actor: user,
              minimum_role: :edit
            )
          RUBY
        },
        {
          title: "Find direct grants with RecordingStudio::Services::AccessCheck.access_recordings_for",
          code: <<~RUBY.strip
            RecordingStudio::Services::AccessCheck.access_recordings_for(recording)
          RUBY
        }
      ]

      render :methods
    end

    def boundaries
      @boundary_sections = [
        {
          title: "What a boundary is",
          body: "Use a boundary when one branch of a workspace needs stricter rules than the rest. For example, a studio can give a client view access to the overall workspace, then place a boundary on an internal review folder with a minimum role of edit. That keeps drafts, notes, and approval checklists inside that folder hidden from the client unless the team adds a direct grant within the bounded area."
        },
        {
          title: "How resolution works",
          body: "AccessCheck looks for direct grants on the current recording and walks upward until it reaches the boundary parent. If it finds a direct grant inside that path, that role wins. If it does not, it checks the inherited role from above the boundary and compares it against the boundary minimum role."
        },
        {
          title: "When access is denied",
          body: "If there is no inherited role above the boundary, or the inherited role is weaker than the boundary minimum, the bounded subtree resolves to no access unless a direct grant exists inside the boundary."
        }
      ]
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
