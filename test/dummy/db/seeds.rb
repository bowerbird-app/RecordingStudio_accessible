# This file should ensure the existence of records required to run the application in every environment.

admin = User.find_or_create_by!(email: "admin@admin.com") do |user|
  user.password = "Password"
  user.password_confirmation = "Password"
end

viewer = User.find_or_create_by!(email: "viewer@admin.com") do |user|
  user.password = "Password"
  user.password_confirmation = "Password"
end

workspace = Workspace.find_or_create_by!(name: "Accessible Studio Workspace")
root_recording = RecordingStudio::Recording.unscoped.find_or_create_by!(recordable: workspace, parent_recording_id: nil)

admin_access = RecordingStudio::Access.find_or_create_by!(actor: admin, role: :admin)
viewer_access = RecordingStudio::Access.find_or_create_by!(actor: viewer, role: :view)

RecordingStudio::Recording.unscoped.find_or_create_by!(
  root_recording_id: root_recording.id,
  parent_recording_id: root_recording.id,
  recordable: admin_access
)

RecordingStudio::Recording.unscoped.find_or_create_by!(
  root_recording_id: root_recording.id,
  parent_recording_id: root_recording.id,
  recordable: viewer_access
)

puts "Seeded: admin@admin.com / Password"
puts "Seeded: viewer@admin.com / Password"
puts "Seeded: Workspace '#{workspace.name}' with root recording ##{root_recording.id}"
