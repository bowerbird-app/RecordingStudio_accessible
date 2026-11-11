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
    RecordingStudioAccessible.configuration.before_access_grant = lambda do |_context|
      raise RecordingStudioAccessible::GrantRefused.new(
        "Every seat is taken.",
        cta_label: "See options",
        cta_path: "/"
      )
    end
  end

  teardown do
    RecordingStudioAccessible.configuration.before_access_grant = @previous_hook
  end

  test "manage access create shows the refusal message and CTA" do
    sign_in @admin

    post root_recording_accesses_path, params: {
      access: { email: @person.email, role: "view" }
    }

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Every seat is taken/
    assert_select "a[href='/']", text: "See options"
    refute RecordingStudioAccessible.authorized?(actor: @person, recording: @root_recording, role: :view)
  end

  test "manage access invite shows the refusal message" do
    sign_in @admin

    post root_recording_accesses_path, params: {
      access: { email: "missing-seat@example.com", role: "view" }
    }

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Every seat is taken/
    assert_select "a[href='/']", text: "See options"
    assert_equal 0, RecordingStudioAccessible::AccessInvitation.where(email: "missing-seat@example.com").count
  end

  test "manage access role change shows the refusal message" do
    RecordingStudioAccessible.configuration.before_access_grant = nil
    grant = RecordingStudioAccessible.grant_access(
      recording: @root_recording, actor: @person, role: :view, manager_actor: @admin
    )
    RecordingStudioAccessible.configuration.before_access_grant = lambda do |_context|
      raise RecordingStudioAccessible::GrantRefused.new(
        "Every seat is taken.",
        cta_label: "See options",
        cta_path: "/"
      )
    end
    sign_in @admin

    patch "#{root_recording_accesses_path}/#{grant.value.id}", params: { access: { role: "edit" } }

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /Every seat is taken/
    assert_select "a[href='/']", text: "See options"
    assert_equal "view", grant.value.reload.recordable.role
  end

  test "access request approval redirects with the refusal message" do
    RecordingStudioAccessible.configuration.before_access_grant = nil
    request_recording = RecordingStudioAccessible.request_access(
      recording: @root_recording, actor: @person, role: :view
    ).value
    RecordingStudioAccessible.configuration.before_access_grant = lambda do |_context|
      raise RecordingStudioAccessible::GrantRefused.new(
        "Every seat is taken.",
        cta_label: "See options",
        cta_path: "/"
      )
    end
    sign_in @admin

    post "/recording_studio_accessible/recordings/#{@root_recording.id}/access_requests/#{request_recording.id}/transition",
         params: { status: "approved", role: "view" }

    assert_response :redirect
    follow_redirect!
    assert_select "[role=alert]", text: /Every seat is taken/
    assert_select "a[href='/']", text: "See options"
    refute RecordingStudioAccessible.authorized?(actor: @person, recording: @root_recording, role: :view)
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def root_recording_accesses_path
    "/recording_studio_accessible/recordings/#{@root_recording.id}/accesses"
  end
end
