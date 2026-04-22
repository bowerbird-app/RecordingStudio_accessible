workspace = Workspace.create!(name: 'Test Workspace')
folder_recording = Recording.create!(recording_type: 'folder', workspace: workspace, name: 'Test Folder')
user = User.create!(email: "test_#{SecureRandom.hex(4)}@example.com", password: 'password', first_name: 'Test', last_name: 'User')

AccessGrant.create!(
  subject: folder_recording,
  actor: user,
  role: 'view',
  workspace: workspace
)

result = RecordingStudioAccessible::Services::GrantRecordingAccess.call(
  recording: folder_recording,
  actor: user,
  role: 'edit'
)

puts "success?: #{result.success?}"
puts "error: #{result.error rescue 'N/A'}"
puts "errors: #{result.errors.full_messages rescue 'N/A'}"

grants = AccessGrant.where(subject: folder_recording, actor: user)
puts "direct grants: #{grants.map { |g| { id: g.id, role: g.role } }}"
