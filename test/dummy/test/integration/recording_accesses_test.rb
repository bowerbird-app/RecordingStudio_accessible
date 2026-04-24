require_relative "../test_helper"

class RecordingAccessesTest < ActionDispatch::IntegrationTest
  setup do
    ActionMailer::Base.deliveries.clear

    @admin = create_user("admin@admin.com")
    @editor = create_user("editor@admin.com")
    @viewer = create_user("viewer@admin.com")
    @new_user = create_user("new_user@admin.com")

    workspace = Workspace.create!(name: "Integration Workspace")
    @root_recording = RecordingStudio::Recording.unscoped.create!(recordable: workspace, parent_recording_id: nil)

    folder = Folder.create!(
      workspace: workspace,
      name: "Client onboarding",
      summary: "Folder-level access",
      position: 0
    )

    @folder_recording = RecordingStudio::Recording.unscoped.create!(
      recordable: folder,
      parent_recording_id: @root_recording.id,
      root_recording_id: @root_recording.id
    )

    grant_access(@admin, :admin, @root_recording)
    grant_access(@editor, :edit, @root_recording)
    grant_access(@viewer, :view, @root_recording)
  end

  test "admin can view the recording access page with the blank engine layout" do
    sign_in @admin

    get root_recording_accesses_path

    assert_response :success
    assert_includes @response.body, "Back"
    assert_includes @response.body, "Manage access"
    assert_includes @response.body, "Integration Workspace"
    assert_includes @response.body, @editor.email
    assert_includes @response.body, "Add access"
    assert_includes @response.body, @admin.email
    assert_includes @response.body, "Integration Workspace"
    refute_includes @response.body, "People with access"
    refute_includes @response.body, "Direct access entries granted on this recording"
    assert_includes @response.body, "<table"
    assert_includes @response.body, "Actor type"
    assert_includes @response.body, "Role"
    assert_includes @response.body, "User"
    assert_includes @response.body, "Edit"
    assert_includes @response.body, %(<form class="inline" method="post" action="#{root_recording_accesses_path}/#{direct_access_recording_for(@editor).id}")
    assert_includes @response.body, %(name="_method" value="delete")
    refute_includes @response.body, "Main navigation"
    refute_includes @response.body, "Sign out"
    refute_includes @response.body, "Other people with access"
    refute_includes @response.body, "other-people-with-access"
    refute_includes @response.body, "Access point"
  end

  test "folder recording access page is available when the recordable has opted in" do
    sign_in @admin

    get recording_accesses_path

    assert_response :success
    assert_includes @response.body, "Client onboarding"
    assert_includes @response.body, "Other people with access"

    post recording_accesses_path, params: {
      access: {
        email: @new_user.email,
        role: "view"
      }
    }

    assert_response :redirect
  end

  test "admin can view the new access page" do
    sign_in @admin

    get "#{root_recording_accesses_path}/new"

    assert_response :success
    assert_includes @response.body, "New access"
    assert_includes @response.body, "Create access"
    assert_includes @response.body, "User email"
    assert_includes @response.body, 'placeholder="email@example.com"'
    refute_includes @response.body, "Select an actor"
    refute_includes @response.body, "<h2>Recording</h2>"
  end

  test "admin can view the edit access page" do
    sign_in @admin

    access_id = direct_access_recording_for(@editor).id

    get "#{root_recording_accesses_path}/#{access_id}/edit"

    assert_response :success
    assert_includes @response.body, "Edit access"
    assert_includes @response.body, @editor.email
    assert_includes @response.body, "Update access"
    refute_includes @response.body, "Edit role"
    refute_includes @response.body, "Change the role or delete this direct access entry"
    refute_includes @response.body, "<h2>Recording</h2>"
  end

  test "non-admin access managers are forbidden" do
    sign_in @viewer

    get root_recording_accesses_path

    assert_response :forbidden

    post root_recording_accesses_path, params: {
      access: {
        email: @new_user.email,
        role: "view"
      }
    }

    assert_response :forbidden
  end

  test "admin can add, edit, and remove direct access" do
    sign_in @admin

    post root_recording_accesses_path, params: {
      access: {
        email: @new_user.email,
        role: "view"
      }
    }

    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_includes @response.body, @new_user.email

    access_recording = direct_access_recording_for(@new_user)
    refute_nil access_recording
    assert_equal "view", access_recording.recordable.role

    patch "#{root_recording_accesses_path}/#{access_recording.id}", params: {
      access: {
        role: "edit"
      }
    }

    assert_response :redirect
    assert_equal 1, direct_access_recordings_for(@new_user).count
    assert_equal "edit", direct_access_recording_for(@new_user).recordable.role

    access_id = direct_access_recording_for(@editor).id
    access_record_id = direct_access_recording_for(@editor).recordable.id

    delete "#{root_recording_accesses_path}/#{access_id}"

    assert_response :redirect
    follow_redirect!
    assert_includes @response.body, "Access removed."
    assert_nil direct_access_recording_for(@editor)
    assert_nil RecordingStudio::Recording.unscoped.find_by(id: access_id)
    assert_nil RecordingStudio::Access.find_by(id: access_record_id)
  end

  test "admin can add access for a new email in the dummy app" do
    sign_in @admin

    post root_recording_accesses_path, params: {
      access: {
        email: "missing@example.com",
        role: "view"
      }
    }

    assert_response :redirect
    follow_redirect!
    assert_includes @response.body, "missing@example.com"
    assert_includes @response.body, "Access granted to missing@example.com"

    missing_user = User.find_by(email: "missing@example.com")
    refute_nil missing_user
    assert_equal "view", direct_access_recording_for(missing_user).recordable.role

    delivery = ActionMailer::Base.deliveries.last
    refute_nil delivery
    assert_equal [ "missing@example.com" ], delivery.to
    assert_equal "You were given access to Integration Workspace", delivery.subject
    assert_includes delivery.body.encoded, "Open the shared item"
  end

  test "granting access deduplicates pre-existing direct grants for the same actor" do
    sign_in @admin

    stale_duplicate = grant_access(@new_user, :view, @root_recording)
    grant_access(@new_user, :edit, @root_recording)

    assert_equal 2, direct_access_recordings_for(@new_user).count

    post root_recording_accesses_path, params: {
      access: {
        email: @new_user.email,
        role: "admin"
      }
    }

    assert_response :redirect

    remaining_recordings = direct_access_recordings_for(@new_user)
    assert_equal 1, remaining_recordings.count
    assert_equal "admin", remaining_recordings.first.recordable.role

    assert_nil RecordingStudio::Recording.unscoped.find_by(id: stale_duplicate.id)
    assert_nil RecordingStudio::Access.find_by(id: stale_duplicate.recordable_id)
  end

  test "admin can still surface a configured missing-user error" do
    sign_in @admin

    with_missing_actor_handler(lambda do |email:, **|
        RecordingStudioAccessible::MissingActorResolution.invalid(
          error: "Resolve #{email} before granting access"
        )
      end) do
      post root_recording_accesses_path, params: {
        access: {
          email: "invited@example.com",
          role: "view"
        }
      }
    end

    assert_response :unprocessable_entity
    assert_includes @response.body, "Resolve invited@example.com before granting access"
    assert_nil User.find_by(email: "invited@example.com")
  end

  test "admin can be redirected into a host-app resolution flow" do
    sign_in @admin

    with_missing_actor_handler(lambda do |controller:, email:, **|
        {
          status: :requires_resolution,
          location: controller.main_app.user_path(@admin),
          alert: "Resolve #{email} before granting access"
        }
      end) do
      post root_recording_accesses_path, params: {
        access: {
          email: "needs-resolution@example.com",
          role: "view"
        }
      }
    end

    assert_response :redirect
    assert_redirected_to "/users/#{@admin.id}"
    follow_redirect!
    assert_includes @response.body, @admin.email
    assert_nil User.find_by(email: "needs-resolution@example.com")
  end

  private

  def with_missing_actor_handler(handler)
    previous_handler = RecordingStudioAccessible.configuration.access_management_missing_actor_handler
    RecordingStudioAccessible.configuration.access_management_missing_actor_handler = handler
    yield
  ensure
    RecordingStudioAccessible.configuration.access_management_missing_actor_handler = previous_handler
  end

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def grant_access(user, role, parent_recording, root_recording = parent_recording)
    access = RecordingStudio::Access.create!(actor: user, role: role)
    RecordingStudio::Recording.unscoped.create!(
      root_recording_id: root_recording.id,
      parent_recording_id: parent_recording.id,
      recordable: access
    )
  end

  def recording_accesses_path
    "/recording_studio_accessible/recordings/#{@folder_recording.id}/accesses"
  end

  def root_recording_accesses_path
    "/recording_studio_accessible/recordings/#{@root_recording.id}/accesses"
  end

  def direct_access_recordings_for(user)
    RecordingStudio::Services::AccessCheck.access_recordings_for(@root_recording)
                                         .select { |recording| recording.recordable.actor == user }
  end

  def direct_access_recording_for(user)
    direct_access_recordings_for(user).first
  end
end
