# This file should ensure the existence of records required to run the application in every environment.

PASSWORD = "Password"

def demo_recording_scope(root_recording)
  base_scope = RecordingStudio::Recording.unscoped

  base_scope.where(id: root_recording.id).or(base_scope.where(root_recording_id: root_recording.id))
end

def upsert_user(email)
  user = User.find_or_initialize_by(email: email)
  user.password = PASSWORD if user.new_record?
  user.password_confirmation = PASSWORD if user.new_record?
  user.save! if user.changed?
  user
end

def upsert_folder(workspace:, name:, summary:, position:)
  folder = workspace.folders.find_or_initialize_by(name: name)
  folder.assign_attributes(summary: summary, position: position)
  folder.save! if folder.changed?
  folder
end

def upsert_page(folder:, title:, summary:, position:)
  page = Page.find_by(folder: folder, title: title)

  if page&.readonly?
    purge_readonly_page(page)
    page = nil
  end

  page ||= Page.new(folder: folder, title: title)
  page.assign_attributes(summary: summary, position: position)
  page.save! if page.changed?
  page
end

def upsert_card(page:, title:, body:, position:)
  card = Card.find_or_initialize_by(page: page, title: title)
  card.assign_attributes(body: body, position: position)
  card.save! if card.changed?
  card
end

def ensure_root_recording(recordable)
  RecordingStudio::Recording.unscoped.find_or_create_by!(recordable: recordable, parent_recording_id: nil)
end

def ensure_child_recording(recordable:, parent_recording:, root_recording:)
  RecordingStudio::Recording.unscoped.find_or_create_by!(
    recordable: recordable,
    parent_recording_id: parent_recording.id,
    root_recording_id: root_recording.id
  )
end

def ensure_access_recording(actor:, role:, parent_recording:, root_recording:)
  access = RecordingStudio::Access.find_or_create_by!(actor: actor, role: role)

  RecordingStudio::Recording.unscoped.find_or_create_by!(
    root_recording_id: root_recording.id,
    parent_recording_id: parent_recording.id,
    recordable: access
  )
end

def delete_orphaned_access(access_id)
  return unless access_id

  return if RecordingStudio::Recording.unscoped.where(recordable_type: "RecordingStudio::Access",
                                                      recordable_id: access_id).exists?

  RecordingStudio::Access.where(id: access_id).delete_all
end

def delete_recording_and_orphaned_access(recording)
  access_id = recording.recordable_type == "RecordingStudio::Access" ? recording.recordable_id : nil

  recording.delete
  delete_orphaned_access(access_id)
end

def purge_readonly_page(page)
  RecordingStudio::Recording.unscoped.where(recordable: page).find_each do |page_recording|
    RecordingStudio::Recording.unscoped
                             .where(parent_recording_id: page_recording.id,
                                    recordable_type: "RecordingStudio::Access",
                                    trashed_at: nil)
                             .find_each do |access_recording|
      delete_recording_and_orphaned_access(access_recording)
    end

    page_recording.delete
  end

  Card.where(page_id: page.id).delete_all
  Page.where(id: page.id).delete_all
end

def remove_invalid_demo_recordings(root_recording)
  loop do
    invalid_recording_ids = demo_recording_scope(root_recording)
                            .where.not(id: root_recording.id)
                            .order(created_at: :desc, id: :desc)
                            .filter_map do |recording|
      recordable_missing = recording.recordable.blank?
      missing_parent = recording.parent_recording_id.present? && recording.parent_recording.blank?

      recording.id if recordable_missing || missing_parent
    end

    break if invalid_recording_ids.empty?

    RecordingStudio::Recording.unscoped.where(id: invalid_recording_ids).find_each do |recording|
      delete_recording_and_orphaned_access(recording)
    end
  end
end

def remove_obsolete_demo_content(workspace:, allowed_pages_by_folder_name:)
  workspace.folders.where.not(name: allowed_pages_by_folder_name.keys).find_each do |folder|
    page_ids = Page.where(folder_id: folder.id).pluck(:id)
    Card.where(page_id: page_ids).delete_all if page_ids.any?
    Page.where(id: page_ids).delete_all if page_ids.any?
    Folder.where(id: folder.id).delete_all
  end

  allowed_pages_by_folder_name.each do |folder_name, allowed_page_titles|
    folder = workspace.folders.find_by(name: folder_name)
    next unless folder

    obsolete_page_ids = Page.where(folder_id: folder.id).where.not(title: allowed_page_titles).pluck(:id)
    next if obsolete_page_ids.empty?

    Card.where(page_id: obsolete_page_ids).delete_all
    Page.where(id: obsolete_page_ids).delete_all
  end
end

def sync_access_recordings(parent_recording:, root_recording:, grants:)
  desired_keys = grants.map { |grant| [ grant.fetch(:actor).class.name, grant.fetch(:actor).id, grant.fetch(:role).to_s ] }
  seen_keys = {}

  RecordingStudio::Recording.unscoped
                           .where(parent_recording_id: parent_recording.id,
                                  root_recording_id: root_recording.id,
                                  recordable_type: "RecordingStudio::Access",
                                  trashed_at: nil)
                           .order(created_at: :asc, id: :asc)
                           .find_each do |recording|
    access = recording.recordable
    key = access && [ access.actor_type, access.actor_id, access.role.to_s ]
    keep = key && access.actor.present? && desired_keys.include?(key) && !seen_keys[key]

    if keep
      seen_keys[key] = true
      next
    end

    delete_recording_and_orphaned_access(recording)
  end

  grants.each do |grant|
    ensure_access_recording(actor: grant.fetch(:actor), role: grant.fetch(:role),
                            parent_recording: parent_recording, root_recording: root_recording)
  end
end

users = {
  admin: upsert_user("admin@admin.com"),
  editor: upsert_user("editor@admin.com"),
  viewer: upsert_user("viewer@admin.com"),
  page_owner: upsert_user("page_owner@admin.com"),
  outsider: upsert_user("outsider@admin.com")
}

workspace = Workspace.find_or_create_by!(name: "Accessible Demo Workspace")
root_recording = ensure_root_recording(workspace)

remove_invalid_demo_recordings(root_recording)

client_onboarding = upsert_folder(
  workspace: workspace,
  name: "Client onboarding",
  summary: "Folder-level edit access demonstrates inherited access on child pages.",
  position: 0
)

operations = upsert_folder(
  workspace: workspace,
  name: "Operations",
  summary: "Folder-level view access keeps the demo focused on read-only collaboration.",
  position: 1
)

welcome_pack = upsert_page(
  folder: client_onboarding,
  title: "Welcome pack",
  summary: "Launch notes for the onboarding flow.",
  position: 0
)

accessibility_checklist = upsert_page(
  folder: client_onboarding,
  title: "Accessibility checklist",
  summary: "Pages inherit access from the folder but cannot host direct access entries.",
  position: 1
)

ops_runbook = upsert_page(
  folder: operations,
  title: "Ops runbook",
  summary: "Read-only operational guidance for the support team.",
  position: 0
)

remove_obsolete_demo_content(
  workspace: workspace,
  allowed_pages_by_folder_name: {
    client_onboarding.name => [ welcome_pack.title, accessibility_checklist.title ],
    operations.name => [ ops_runbook.title ]
  }
)

remove_invalid_demo_recordings(root_recording)

[
  { page: welcome_pack, title: "Share credentials", body: "Send the starter account details and confirm sign-in.", position: 0 },
  { page: welcome_pack, title: "Confirm first steps", body: "Review the initial tasks for the client workspace.", position: 1 },
  { page: accessibility_checklist, title: "Contrast review", body: "Capture color contrast fixes before sign-off.", position: 0 },
  { page: accessibility_checklist, title: "Keyboard testing", body: "Verify the primary flows without a pointer.", position: 1 },
  { page: ops_runbook, title: "Escalation path", body: "List the owners for urgent operational issues.", position: 0 }
].each do |attributes|
  upsert_card(**attributes)
end

client_onboarding_recording = ensure_child_recording(
  recordable: client_onboarding,
  parent_recording: root_recording,
  root_recording: root_recording
)

operations_recording = ensure_child_recording(
  recordable: operations,
  parent_recording: root_recording,
  root_recording: root_recording
)

accessibility_checklist_recording = ensure_child_recording(
  recordable: accessibility_checklist,
  parent_recording: client_onboarding_recording,
  root_recording: root_recording
)

welcome_pack_recording = ensure_child_recording(
  recordable: welcome_pack,
  parent_recording: client_onboarding_recording,
  root_recording: root_recording
)

ops_runbook_recording = ensure_child_recording(
  recordable: ops_runbook,
  parent_recording: operations_recording,
  root_recording: root_recording
)

sync_access_recordings(
  parent_recording: root_recording,
  root_recording: root_recording,
  grants: [
    { actor: users[:admin], role: :admin }
  ]
)

sync_access_recordings(
  parent_recording: client_onboarding_recording,
  root_recording: root_recording,
  grants: [
    { actor: users[:editor], role: :edit }
  ]
)

sync_access_recordings(
  parent_recording: operations_recording,
  root_recording: root_recording,
  grants: [
    { actor: users[:viewer], role: :view }
  ]
)

[ welcome_pack_recording, accessibility_checklist_recording, ops_runbook_recording ].each do |page_recording|
  sync_access_recordings(
    parent_recording: page_recording,
    root_recording: root_recording,
    grants: []
  )
end

puts "Seeded folder direct access: #{client_onboarding.name} (editor), #{operations.name} (viewer)"

users.except(:page_owner).each_value do |user|
  puts "Seeded: #{user.email} / #{PASSWORD}"
end

puts "Seeded without direct page access for pages: #{welcome_pack.title}, #{accessibility_checklist.title}, #{ops_runbook.title}"

puts "Seeded: Workspace '#{workspace.name}' with #{workspace.folders.count} folders"
