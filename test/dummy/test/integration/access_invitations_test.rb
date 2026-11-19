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

  test "a signed-out invite visit records via share and the invitation recording" do
    token = deliver_invitation("share-source@example.com")
    invitation = RecordingStudioAccessible::AccessInvitation.find_by!(email: "share-source@example.com")

    get invitation_path(token)

    assert_redirected_to "/invitation_signups/#{token}/new"
    assert_equal({ via: "share", recording_id: invitation.recording_id }, signup_source)
  end

  test "a signed-out invite accept records via share and the invitation recording" do
    token = deliver_invitation("share-accept@example.com")
    invitation = RecordingStudioAccessible::AccessInvitation.find_by!(email: "share-accept@example.com")

    post "/recording_studio_accessible/access_invitations/#{token}/accept"

    assert_redirected_to "/invitation_signups/#{token}/new"
    assert_equal({ via: "share", recording_id: invitation.recording_id }, signup_source)
    refute invitation.reload.accepted?
  end

  test "a source param and a tampered recording_id are ignored on an invite visit" do
    token = deliver_invitation("tampered-invite@example.com")
    invitation = RecordingStudioAccessible::AccessInvitation.find_by!(email: "tampered-invite@example.com")
    decoy = create_root_recording(Workspace.create!(name: "Decoy Invite Target"))

    get invitation_path(token), params: {
      source: { via: "access_request", recording_id: decoy.id },
      recording_id: decoy.id
    }

    assert_redirected_to "/invitation_signups/#{token}/new"
    assert_equal({ via: "share", recording_id: invitation.recording_id }, signup_source)
  end

  test "an invalid invite token records no signup source" do
    get invitation_path("a" * 32), params: {
      source: { via: "share", recording_id: @recording.id },
      recording_id: @recording.id
    }

    assert_response :not_found
    assert_nil signup_source
  end

  test "an expired invite token records no signup source" do
    token = deliver_invitation("expired-invite@example.com")
    invitation = RecordingStudioAccessible::AccessInvitation.find_by!(email: "expired-invite@example.com")
    invitation.update!(expires_at: 1.minute.ago)

    get invitation_path(token), params: { source: { via: "share" }, recording_id: @recording.id }

    assert_redirected_to "/invitation_signups/#{token}/new"
    assert_nil signup_source
  end

  test "a revoked invite token records no signup source" do
    token = deliver_invitation("revoked-invite@example.com")
    invitation = RecordingStudioAccessible::AccessInvitation.find_by!(email: "revoked-invite@example.com")
    result = RecordingStudioAccessible.revoke_access_invitation(invitation: invitation, manager_actor: @admin)
    assert result.success?, result.error

    get invitation_path(token), params: { source: { via: "share" }, recording_id: @recording.id }

    assert_redirected_to "/invitation_signups/#{token}/new"
    assert_nil signup_source
  end

  test "a signed-in invite visit records no signup source and acceptance still grants" do
    token = deliver_invitation("signed-in-invite@example.com")
    user = User.create!(
      email: "signed-in-invite@example.com",
      password: "Password",
      password_confirmation: "Password"
    )
    sign_in user

    get invitation_path(token), params: { source: { via: "share", recording_id: 0 } }

    assert_response :success
    assert_nil signup_source

    assert_difference -> { RecordingStudio::Access.count }, 1 do
      post "/recording_studio_accessible/access_invitations/#{token}/accept"
    end

    assert_nil signup_source
    assert RecordingStudioAccessible.authorized?(actor: user, recording: @recording, role: :view)
    assert RecordingStudioAccessible::AccessInvitation.find_by!(email: "signed-in-invite@example.com").accepted?
  end

  test "a signed-out invite redirect still works when Users has no signup source method" do
    token = deliver_invitation("old-users-invite@example.com")

    without_signup_source_method do
      get invitation_path(token)

      assert_redirected_to "/invitation_signups/#{token}/new"
      assert_nil signup_source
    end
  end

  test "a signed-out invite redirect still works when Users is missing" do
    token = deliver_invitation("missing-users-invite@example.com")
    session_key = RecordingStudioUser::SignupSource::SESSION_KEY

    without_recording_studio_user do
      get invitation_path(token)

      assert_redirected_to "/invitation_signups/#{token}/new"
      assert_nil session[session_key]
    end
  end

  private

  def invitation_path(token)
    "/recording_studio_accessible/access_invitations/#{token}"
  end

  def deliver_invitation(email)
    sign_in @admin
    post "/recording_studio_accessible/recordings/#{@recording.id}/accesses", params: {
      access: { email: email, role: "view" }
    }
    token = ActionMailer::Base.deliveries.last.body.encoded[/access_invitations\/([A-Za-z0-9_-]+)/, 1]
    sign_out @admin
    assert token.present?
    token
  end

  def signup_source
    RecordingStudioUser::SignupSource.read(session)
  end

  def without_signup_source_method
    singleton = RecordingStudioUser.singleton_class
    singleton.alias_method(:__original_remember_signup_source!, :remember_signup_source!)
    singleton.send(:undef_method, :remember_signup_source!)
    yield
  ensure
    unless RecordingStudioUser.respond_to?(:remember_signup_source!)
      singleton.alias_method(:remember_signup_source!, :__original_remember_signup_source!)
    end
    singleton.send(:undef_method, :__original_remember_signup_source!)
  end

  def without_recording_studio_user
    removed = Object.send(:remove_const, :RecordingStudioUser)
    yield
  ensure
    Object.const_set(:RecordingStudioUser, removed) unless defined?(::RecordingStudioUser)
  end
end
