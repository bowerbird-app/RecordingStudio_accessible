# Deep debug into 403
admin = User.find_by(email: 'admin@admin.com')
workspace = Workspace.find_by(name: 'Test Workspace')
root = RecordingStudio::Recording.unscoped.find_by(recordable: workspace, parent_recording_id: nil)

app = ActionDispatch::Integration::Session.new(Rails.application)
app.post '/users/sign_in', params: { user: { email: 'admin@admin.com', password: 'Password' } }

# If still 403, let's see what the exception was if possible
if app.response.status == 403
  puts "403 encountered."
  # Rails sometimes includes the exception in env for error pages
  if app.controller && app.controller.instance_variable_get(:@_exception)
    puts "Exception: #{app.controller.instance_variable_get(:@_exception).message}"
  end
end

# Check the controller and action associated with the 403
puts "Request path: #{app.request.path}"
puts "Controller: #{app.controller.class.name if app.controller}"

# Try to look for any middleware that might be returning 403 (like Rack::Attack or similar)
