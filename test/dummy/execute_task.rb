require 'ostruct'
# Initialize objects
email_admin = 'admin@admin.com'
email_target = 'target@example.com'
password = 'Password'

admin = User.find_or_create_by!(email: email_admin) { |u| u.password = password; u.first_name = "Admin"; u.last_name = "User" }
target = User.find_or_create_by!(email: email_target) { |u| u.password = password; u.first_name = "Target"; u.last_name = "User" }

workspace = Workspace.find_or_create_by!(name: 'Test Workspace')
root = RecordingStudio::Recording.unscoped.find_or_create_by!(recordable: workspace, parent_recording_id: nil)

access_actor = RecordingStudio::Access.find_or_initialize_by(actor: admin, role: :admin)
unless RecordingStudio::Recording.unscoped.exists?(root_recording_id: root.id, parent_recording_id: root.id, recordable: access_actor)
  access_actor.save!
  RecordingStudio::Recording.unscoped.create!(root_recording_id: root.id, parent_recording_id: root.id, recordable: access_actor)
end

# Correct Controller Name
controller = RecordingStudioAccessible::RecordingAccessesController.new
request = ActionDispatch::TestRequest.create
# Mock Warden
warden = OpenStruct.new({
  user: admin,
  authenticate!: admin,
  authenticated?: true,
  raw_session: {},
  'request_env' => {}
})
request.env['warden'] = warden
# Initialize params via ActionController::Parameters
params = ActionController::Parameters.new({
  recording_id: root.id,
  access: { email: email_target, role: 'view' }
})
request.instance_variable_set(:@params, params)

# Mock response
response = ActionDispatch::TestResponse.new
controller.set_request! request
controller.set_response! response

begin
  controller.process(:create)
  puts "Status: #{response.status}"
  if response.status == 302
    puts "Redirected to: #{response.location}"
    flash = request.env['action_dispatch.request.flash_hash']
    puts "Flash: #{flash.to_h}" if flash
  else
    puts "Body summary: #{response.body[0..500]}"
  end
rescue => e
  puts "Error: #{e.class} - #{e.message}"
end
