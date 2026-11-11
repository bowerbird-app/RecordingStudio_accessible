# frozen_string_literal: true

require_relative "../test_helper"

class GrantRefusedAccessTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user("grant-refused-admin@example.com")
    @person = create_user("grant-refused-person@example.com")
    workspace = Workspace.create!(name: "Grant Refused Workspace")
    @root_recording = create_root_recording(workspace)
    create_direct_access_recording(actor: @admin, role: :admin, parent_recording: @root_recording)
    @previous_hook = RecordingStudioAccessible.configuration.before_access_grant
  end

  teardown do
    RecordingStudioAccessible.configuration.before_access_grant = @previous_hook
  end

  test "share access has no gate button" do
    sign_in @admin

    get "#{root_recording_accesses_path}/new"

    assert_response :success
    assert_includes @response.body, "Share access"
    refute_includes @response.body, "See options"
    refute_match(/href=["']\/plans["']/, @response.body)
  end

  test "manage access create stays on the form when redirect_to is absent" do
    refuse_without_redirect
    sign_in @admin

    post root_recording_accesses_path, params: {
      access: { email: @person.email, role: "view" }
    }

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Every seat is taken/
    refute_includes @response.body, "See options"
    refute RecordingStudioAccessible.authorized?(actor: @person, recording: @root_recording, role: :view)
  end

  test "manage access create redirects to the host path when redirect_to is set" do
    refuse_with_redirect
    sign_in @admin

    post root_recording_accesses_path, params: {
      access: { email: @person.email, role: "view" }
    }

    assert_redirected_to "/plans"
    follow_redirect!
    assert_select "[role=alert]", text: /Every seat is taken/
    assert_includes @response.body, "Plans"
    refute_includes @response.body, "See options"
    refute RecordingStudioAccessible.authorized?(actor: @person, recording: @root_recording, role: :view)
  end

  test "manage access invite redirects to the host path" do
    refuse_with_redirect
    sign_in @admin

    post root_recording_accesses_path, params: {
      access: { email: "missing-seat@example.com", role: "view" }
    }

    assert_redirected_to "/plans"
    follow_redirect!
    assert_select "[role=alert]", text: /Every seat is taken/
    assert_equal 0, RecordingStudioAccessible::AccessInvitation.where(email: "missing-seat@example.com").count
  end

  test "manage access role change redirects to the host path" do
    grant = RecordingStudioAccessible.grant_access(
      recording: @root_recording, actor: @person, role: :view, manager_actor: @admin
    )
    refuse_with_redirect
    sign_in @admin

    patch "#{root_recording_accesses_path}/#{grant.value.id}", params: { access: { role: "edit" } }

    assert_redirected_to "/plans"
    follow_redirect!
    assert_select "[role=alert]", text: /Every seat is taken/
    assert_equal "view", grant.value.reload.recordable.role
  end

  test "manage access role change stays on edit when redirect_to is absent" do
    grant = RecordingStudioAccessible.grant_access(
      recording: @root_recording, actor: @person, role: :view, manager_actor: @admin
    )
    refuse_without_redirect
    sign_in @admin

    patch "#{root_recording_accesses_path}/#{grant.value.id}", params: { access: { role: "edit" } }

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Every seat is taken/
    refute_includes @response.body, "See options"
    assert_equal "view", grant.value.reload.recordable.role
  end

  test "access request approval redirects to the host path" do
    request_recording = RecordingStudioAccessible.request_access(
      recording: @root_recording, actor: @person, role: :view
    ).value
    refuse_with_redirect
    sign_in @admin

    post "/recording_studio_accessible/recordings/#{@root_recording.id}/access_requests/#{request_recording.id}/transition",
         params: { status: "approved", role: "view" }

    assert_redirected_to "/plans"
    follow_redirect!
    assert_select "[role=alert]", text: /Every seat is taken/
    refute RecordingStudioAccessible.authorized?(actor: @person, recording: @root_recording, role: :view)
  end

  test "unset hook renders the new access page and the invitation page" do
    sign_in @admin
    token = invitation_token_for("page-open@example.com")

    get "#{root_recording_accesses_path}/new"

    assert_response :success
    assert_includes @response.body, "Share access"
    assert_includes @response.body, "Give access"

    get "/recording_studio_accessible/access_invitations/#{token}"

    assert_response :success
    assert_includes @response.body, "Accept invitation"
  end

  test "allowing hook renders both pages with a nil role and nil grantee" do
    seen = []
    RecordingStudioAccessible.configuration.before_access_grant = lambda do |context|
      seen << context
    end
    sign_in @admin
    token = invitation_token_for("page-allow@example.com")
    seen.clear

    get "#{root_recording_accesses_path}/new"

    assert_response :success
    assert_includes @response.body, "Give access"
    access_context = seen.last
    assert_equal :new_access, access_context.source
    assert_nil access_context.role
    assert_nil access_context.actor
    assert_nil access_context.previous_role
    assert_equal @admin, access_context.granted_by
    assert_equal @root_recording, access_context.recording

    get "/recording_studio_accessible/access_invitations/#{token}"

    assert_response :success
    assert_includes @response.body, "Accept invitation"
    invitation_context = seen.last
    assert_equal :new_invitation, invitation_context.source
    assert_nil invitation_context.role
    assert_nil invitation_context.actor
    assert_equal @admin, invitation_context.granted_by
    assert_equal @root_recording, invitation_context.recording
  end

  test "GrantRefused with redirect_to leaves both pages" do
    refuse_with_redirect
    sign_in @admin
    token = invitation_token_for("page-redirect@example.com")
    refuse_with_redirect

    get "#{root_recording_accesses_path}/new"

    assert_redirected_to "/plans"
    follow_redirect!
    assert_select "[role=alert]", text: /Every seat is taken/

    get "/recording_studio_accessible/access_invitations/#{token}"

    assert_redirected_to "/plans"
    follow_redirect!
    assert_select "[role=alert]", text: /Every seat is taken/
  end

  test "GrantRefused without redirect shows the refusal on both pages" do
    refuse_without_redirect
    sign_in @admin
    token = invitation_token_for("page-alert@example.com")
    refuse_without_redirect

    get "#{root_recording_accesses_path}/new"

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Every seat is taken/

    get "/recording_studio_accessible/access_invitations/#{token}"

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Every seat is taken/
  end

  test "another error on either page does not render the form" do
    sign_in @admin
    token = invitation_token_for("page-boom@example.com")
    RecordingStudioAccessible.configuration.before_access_grant = ->(_context) { raise "boom" }

    error = assert_raises(RuntimeError) { get "#{root_recording_accesses_path}/new" }
    assert_equal "boom", error.message

    error = assert_raises(RuntimeError) { get "/recording_studio_accessible/access_invitations/#{token}" }
    assert_equal "boom", error.message
  end

  test "a person with no access is denied and the hook is not called" do
    outsider = create_user("page-gate-outsider@example.com")
    called = false
    RecordingStudioAccessible.configuration.before_access_grant = lambda do |_context|
      called = true
    end
    sign_in outsider

    get "#{root_recording_accesses_path}/new"

    assert_response :forbidden
    refute called
  end

  test "an unsigned invitation visit redirects before the hook" do
    sign_in @admin
    token = invitation_token_for("page-unsigned@example.com")
    called = false
    RecordingStudioAccessible.configuration.before_access_grant = lambda do |_context|
      called = true
    end
    sign_out @admin

    get "/recording_studio_accessible/access_invitations/#{token}"

    assert_response :redirect
    refute_equal "/plans", URI.parse(@response.redirect_url).path
    refute called
  end

  test "a direct post is still refused when the page sources are allowed" do
    allow_pages_and_refuse_writes
    sign_in @admin

    get "#{root_recording_accesses_path}/new"

    assert_response :success
    assert_includes @response.body, "Give access"

    post root_recording_accesses_path, params: {
      access: { email: @person.email, role: "view" }
    }

    assert_redirected_to "/plans"
    refute RecordingStudioAccessible.authorized?(actor: @person, recording: @root_recording, role: :view)

    post root_recording_accesses_path, params: {
      access: { email: "bypassed-invite@example.com", role: "view" }
    }

    assert_redirected_to "/plans"
    assert_equal 0, RecordingStudioAccessible::AccessInvitation.where(email: "bypassed-invite@example.com").count
  end

  test "an allowing hook still lets a direct post grant access" do
    seen = []
    RecordingStudioAccessible.configuration.before_access_grant = lambda do |context|
      seen << context
    end
    sign_in @admin

    post root_recording_accesses_path, params: {
      access: { email: @person.email, role: "view" }
    }

    assert_response :redirect
    refute_equal "/plans", URI.parse(@response.redirect_url).path
    assert RecordingStudioAccessible.authorized?(actor: @person, recording: @root_recording, role: :view)
    assert_equal :grant, seen.last.source
    assert_equal @person, seen.last.actor
    assert_equal "view", seen.last.role
  end

  test "access request approval stays on review when redirect_to is absent" do
    request_recording = RecordingStudioAccessible.request_access(
      recording: @root_recording, actor: @person, role: :view
    ).value
    refuse_without_redirect
    sign_in @admin

    post "/recording_studio_accessible/recordings/#{@root_recording.id}/access_requests/#{request_recording.id}/transition",
         params: { status: "approved", role: "view" }

    assert_response :redirect
    refute_equal "/plans", URI.parse(@response.redirect_url).path
    follow_redirect!
    assert_select "[role=alert]", text: /Every seat is taken/
    refute_includes @response.body, "See options"
    refute RecordingStudioAccessible.authorized?(actor: @person, recording: @root_recording, role: :view)
  end

  private

  def refuse_without_redirect
    RecordingStudioAccessible.configuration.before_access_grant = lambda do |_context|
      raise RecordingStudioAccessible::GrantRefused.new("Every seat is taken.")
    end
  end

  def refuse_with_redirect
    RecordingStudioAccessible.configuration.before_access_grant = lambda do |_context|
      raise RecordingStudioAccessible::GrantRefused.new("Every seat is taken.", redirect_to: "/plans")
    end
  end

  def allow_pages_and_refuse_writes
    RecordingStudioAccessible.configuration.before_access_grant = lambda do |context|
      next if RecordingStudioAccessible::GrantContext::PAGE_SOURCES.include?(context.source)

      raise RecordingStudioAccessible::GrantRefused.new("Every seat is taken.", redirect_to: "/plans")
    end
  end

  def invitation_token_for(email)
    previous = RecordingStudioAccessible.configuration.before_access_grant
    RecordingStudioAccessible.configuration.before_access_grant = nil
    ActionMailer::Base.deliveries.clear

    post root_recording_accesses_path, params: { access: { email: email, role: "view" } }

    assert_response :redirect
    token = ActionMailer::Base.deliveries.last.body.encoded[/access_invitations\/([A-Za-z0-9_-]+)/, 1]
    assert token
    token
  ensure
    RecordingStudioAccessible.configuration.before_access_grant = previous
  end

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def root_recording_accesses_path
    "/recording_studio_accessible/recordings/#{@root_recording.id}/accesses"
  end
end
