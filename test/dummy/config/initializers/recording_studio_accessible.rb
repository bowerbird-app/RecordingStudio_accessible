# frozen_string_literal: true

require "securerandom"

RecordingStudioAccessible.configure do |config|
  config.access_actor_types = [ "User" ]

  config.authorize_actor_through = lambda do |actor:, through:, **|
    case through
    when Workspace
      workspace_root = RecordingStudio.root_recording_for(through)

      RecordingStudioAccessible.authorized?(
        actor: actor,
        recording: workspace_root,
        role: :view
      )
    else
      actor == through
    end
  end

  config.avatar_resolver = lambda do |access_holder|
    next unless access_holder.is_a?(User)

    email = access_holder.email.to_s.strip
    next if email.blank?

    {
      name: email.split("@").first.tr("._-", " ").squish.titleize,
      alt: email,
      href: "/users/#{access_holder.id}"
    }
  end

  config.access_management_missing_actor_handler = lambda do |email:, **|
    normalized_email = email.to_s.strip.downcase

    next RecordingStudioAccessible::MissingActorResolution.invalid(error: "User is required") if normalized_email.blank?

    user = User.find_or_initialize_by(email: normalized_email)

    if user.new_record?
      password = SecureRandom.hex(12)
      user.password = password
      user.password_confirmation = password
      user.save!
    end

    RecordingStudioAccessible::MissingActorResolution.created(
      actor: user,
      notice: "Access granted to #{normalized_email}"
    )
  end
end

# -- Demo: action authorization registry -----------------------------------
# Two example actions registered to demo the ActionRegistry:
# - :manage_workspace — allowed for the current demo admin
# - :export_data — intentionally denied for the current demo admin so the UI
#   shows one approved action and one denied action
RecordingStudioAccessible.register_action(
  :manage_workspace,
  label: "Manage workspace",
  description: "Edit workspace name, delete the workspace, or manage billing.",
  source: "recording_studio_accessible_demo",
  recording_required: true
)

RecordingStudioAccessible.register_action(
  :export_data,
  label: "Export data",
  description: "Export all workspace data as a ZIP archive.",
  source: "recording_studio_accessible_demo",
  recording_required: true
)

# Reusable check used by both action policies.
RecordingStudioAccessible.define_check(:workspace_admin) do |actor:, **|
  workspace = Workspace.order(:name).first
  next false unless workspace

  root = RecordingStudio.root_recording_for(workspace)
  next false unless root

  RecordingStudioAccessible.authorized?(actor: actor, recording: root, role: :admin)
end

RecordingStudioAccessible.define_check(:demo_exporter) do |actor:, **|
  actor&.email.to_s.strip.casecmp?("exporter@admin.com")
end

RecordingStudioAccessible.define_action(:manage_workspace) do |actor:, **|
  RecordingStudioAccessible.check(:workspace_admin, actor: actor)
end

RecordingStudioAccessible.define_action(:export_data) do |actor:, recording:, **|
  recording.present? && RecordingStudioAccessible.check(:demo_exporter, actor: actor)
end
