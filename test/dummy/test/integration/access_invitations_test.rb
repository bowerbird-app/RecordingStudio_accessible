# frozen_string_literal: true

require_relative "../test_helper"

class AccessInvitationsTest < ActionDispatch::IntegrationTest
  setup do
    ActionMailer::Base.deliveries.clear
    @admin = User.find_by(email: "admin@admin.com") ||
             User.create!(email: "admin@admin.com", password: "Password", password_confirmation: "Password")
    workspace = Workspace.create!(name: "Signup Workspace")
    @recording = create_root_recording(workspace)
    bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(recording: @recording, actor: @admin)
    assert bootstrap.success?, bootstrap.error
  end

  test "signup page does not create a user until the password is submitted" do
    sign_in @admin
    post "/recording_studio_accessible/recordings/#{@recording.id}/accesses", params: {
      access: { email: "signup@example.com", role: "view" }
    }
    assert_equal "Invitation sent.", flash[:notice]
    token = ActionMailer::Base.deliveries.last.body.encoded[/access_invitations\/([A-Za-z0-9_-]+)/, 1]
    sign_out @admin

    get "/recording_studio_accessible/access_invitations/#{token}"
    assert_redirected_to "/invitation_signups/#{token}/new"

    assert_no_difference -> { User.count } do
      get "/invitation_signups/#{token}/new"
    end

    assert_response :success
    assert_includes @response.body, "signup@example.com"
    assert_nil User.find_by(email: "signup@example.com")

    assert_difference -> { User.count }, 1 do
      assert_difference -> { RecordingStudio::Access.count }, 1 do
        post "/invitation_signups/#{token}/create", params: {
          invitation_signup: { password: "Password" }
        }
      end
    end

    user = User.find_by!(email: "signup@example.com")
    assert_redirected_to "/"
    assert_equal "Access granted.", flash[:notice]
    assert RecordingStudioAccessible.authorized?(actor: user, recording: @recording, role: :view)
    assert_equal :view, RecordingStudioAccessible.role_for(actor: user, recording: @recording)
    invitation = RecordingStudioAccessible::AccessInvitation.find_by!(email: "signup@example.com")
    assert invitation.accepted?
    assert user.created_at >= invitation.created_at
  end

  test "signup tells an existing user to sign in" do
    sign_in @admin
    post "/recording_studio_accessible/recordings/#{@recording.id}/accesses", params: {
      access: { email: "already@example.com", role: "view" }
    }
    token = ActionMailer::Base.deliveries.last.body.encoded[/access_invitations\/([A-Za-z0-9_-]+)/, 1]
    User.create!(email: "already@example.com", password: "Password", password_confirmation: "Password")
    sign_out @admin

    assert_no_difference -> { User.count } do
      post "/invitation_signups/#{token}/create", params: {
        invitation_signup: { password: "Password" }
      }
    end

    assert_response :unprocessable_entity
    assert_includes @response.body, "already exists"
    assert_includes @response.body, "Sign in"
    refute RecordingStudioAccessible::AccessInvitation.find_by!(email: "already@example.com").accepted?
  end
end
