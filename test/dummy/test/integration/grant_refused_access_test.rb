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

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def root_recording_accesses_path
    "/recording_studio_accessible/recordings/#{@root_recording.id}/accesses"
  end
end
