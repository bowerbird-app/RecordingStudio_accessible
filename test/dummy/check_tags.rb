class TagChecker < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def run_check
    host! "localhost"

    email = "admin_#{Time.now.to_i}@admin.com"
    admin = User.create!(email: email, password: "Password", password_confirmation: "Password")
    workspace = Workspace.create!(name: "Runner Workspace")
    root_recording = RecordingStudio::Recording.unscoped.create!(recordable: workspace, parent_recording_id: nil)

    folder = Folder.create!(
      workspace: workspace,
      name: "Runner Folder",
      summary: "Folder-level access",
      position: 0
    )

    folder_recording = RecordingStudio::Recording.unscoped.create!(
      recordable: folder,
      parent_recording_id: root_recording.id,
      root_recording_id: root_recording.id
    )

    grant_access(admin, :admin, root_recording)

    path = "/recording_studio_accessible/recordings/#{folder_recording.id}/accesses"

    sign_in admin
    get path

    puts "ACCESSING: #{path}"
    puts "STATUS: #{response.status}"
    puts "--- HEAD TAGS ---"
    puts response.body.scan(/<(?:link|script)[^>]*>/).join("\n")
    puts "---"

    tags = response.body.scan(/<(?:link|script)[^>]*>/).join(" ")

    [
      "flat_pack/variables",
      "flat_pack/application",
      "application",
      "tailwind",
      "javascript_importmap_tags"
    ].each do |term|
      present = tags.include?(term)
      puts "#{term} present: #{present}"
    end

    puts "importmap present: #{tags.include?('importmap')}"
  end

  private

  def grant_access(user, role, parent_recording, root_recording = parent_recording)
    access = RecordingStudio::Access.create!(actor: user, role: role)
    RecordingStudio::Recording.unscoped.create!(
      root_recording_id: root_recording.id,
      parent_recording_id: parent_recording.id,
      recordable: access
    )
  end
end

checker = TagChecker.new(:foo)
checker.run_check
