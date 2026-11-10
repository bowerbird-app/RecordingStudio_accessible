# frozen_string_literal: true

require "test_helper"

class AccessApiActionsRequestTest < ActionDispatch::IntegrationTest
  setup do
    skip "Recording Studio API is not loaded" unless defined?(RecordingStudioApi)

    @admin = create_user("api-request-admin@example.com")
    @editor = create_user("api-request-editor@example.com")
    @viewer = create_user("api-request-viewer@example.com")
    @workspace = Workspace.create!(name: "Dispatcher Workspace")
    @root = create_root_recording(@workspace)
    @admin_access = create_direct_access_recording(actor: @admin, role: :admin, parent_recording: @root)
    @editor_access = create_direct_access_recording(actor: @editor, role: :edit, parent_recording: @root)
    @viewer_access = create_direct_access_recording(actor: @viewer, role: :view, parent_recording: @root)

    @other_workspace = Workspace.create!(name: "Other Dispatcher Workspace")
    @other_root = create_root_recording(@other_workspace)
    @other_admin = create_user("api-request-other-admin@example.com")
    create_direct_access_recording(actor: @other_admin, role: :admin, parent_recording: @other_root)
  end

  test "admin list_access is 200 through the dispatcher" do
    post_access_action(@root, :list_access, token_for(@admin_access, "Admin list"))

    assert_response :success
    grants = JSON.parse(response.body).fetch("grants")
    labels = grants.map { |row| row.dig("actor", "label") }
    assert_includes labels, @admin.email
  end

  test "editor and viewer list_access are 403 through the dispatcher" do
    post_access_action(@root, :list_access, token_for(@editor_access, "Editor list"))
    assert_response :forbidden

    post_access_action(@root, :list_access, token_for(@viewer_access, "Viewer list"))
    assert_response :forbidden
  end

  test "cross-root list_access is 404 through the dispatcher" do
    post_access_action(@other_root, :list_access, token_for(@admin_access, "Cross-root list"))

    assert_response :not_found
  end

  test "admin grant is 200 and editor grant is 403 through the dispatcher" do
    invitee = create_user("api-request-invitee@example.com")
    post_access_action(
      @root,
      :grant_access,
      token_for(@admin_access, "Admin grant"),
      params: { actor_id: invitee.id.to_s, actor_type: "User", role: "view" }
    )
    assert_response :success
    assert RecordingStudioAccessible.authorized?(actor: invitee, recording: @root, role: :view)

    post_access_action(
      @root,
      :grant_access,
      token_for(@editor_access, "Editor grant"),
      params: { actor_id: @viewer.id.to_s, actor_type: "User", role: "view" }
    )
    assert_response :forbidden
  end

  test "viewer grant is 403 through the dispatcher" do
    post_access_action(
      @root,
      :grant_access,
      token_for(@viewer_access, "Viewer grant"),
      params: { actor_id: @editor.id.to_s, actor_type: "User", role: "view" }
    )

    assert_response :forbidden
  end

  test "cross-root grant is 404 through the dispatcher" do
    post_access_action(
      @other_root,
      :grant_access,
      token_for(@admin_access, "Cross-root grant"),
      params: { email: "cross-root-grant@example.com", role: "view" }
    )

    assert_response :not_found
    refute RecordingStudioAccessible::AccessInvitation.exists?(email: "cross-root-grant@example.com")
  end

  test "admin update_access is 200 through the dispatcher" do
    post_access_action(
      @root,
      :update_access,
      token_for(@admin_access, "Admin update"),
      params: { actor_id: @editor.id.to_s, actor_type: "User", role: "view" }
    )

    assert_response :success
    assert_equal :view, RecordingStudioAccessible.role_for(actor: @editor, recording: @root)
  end

  test "editor and viewer update_access are 403 through the dispatcher" do
    post_access_action(
      @root,
      :update_access,
      token_for(@editor_access, "Editor update"),
      params: { actor_id: @viewer.id.to_s, actor_type: "User", role: "view" }
    )
    assert_response :forbidden

    post_access_action(
      @root,
      :update_access,
      token_for(@viewer_access, "Viewer update"),
      params: { actor_id: @editor.id.to_s, actor_type: "User", role: "view" }
    )
    assert_response :forbidden
  end

  test "cross-root update_access is 404 through the dispatcher" do
    post_access_action(
      @other_root,
      :update_access,
      token_for(@admin_access, "Cross-root update"),
      params: { actor_id: @other_admin.id.to_s, actor_type: "User", role: "view" }
    )

    assert_response :not_found
  end

  test "admin revoke_access is 200 through the dispatcher" do
    invitee = create_user("api-request-revokee@example.com")
    create_direct_access_recording(actor: invitee, role: :view, parent_recording: @root)

    post_access_action(
      @root,
      :revoke_access,
      token_for(@admin_access, "Admin revoke"),
      params: { actor_id: invitee.id.to_s, actor_type: "User" }
    )

    assert_response :success
    refute RecordingStudioAccessible.authorized?(actor: invitee, recording: @root, role: :view)
  end

  test "editor and viewer revoke_access are 403 through the dispatcher" do
    post_access_action(
      @root,
      :revoke_access,
      token_for(@editor_access, "Editor revoke"),
      params: { actor_id: @viewer.id.to_s, actor_type: "User" }
    )
    assert_response :forbidden

    post_access_action(
      @root,
      :revoke_access,
      token_for(@viewer_access, "Viewer revoke"),
      params: { actor_id: @editor.id.to_s, actor_type: "User" }
    )
    assert_response :forbidden
  end

  test "cross-root revoke_access is 404 through the dispatcher" do
    post_access_action(
      @other_root,
      :revoke_access,
      token_for(@admin_access, "Cross-root revoke"),
      params: { actor_id: @other_admin.id.to_s, actor_type: "User" }
    )

    assert_response :not_found
  end

  private

  def post_access_action(recording, action_name, token, params: {})
    post "/recording_studio_api/api/v1/workspaces/#{recording.id}/actions/#{action_name}",
         params: params,
         as: :json,
         headers: { "Authorization" => "Bearer #{token}" }
  end

  def token_for(access_recording, name)
    previous_types = RecordingStudioAccessible.configuration.access_actor_types
    RecordingStudioAccessible.configuration.access_actor_types =
      Array(previous_types) | ["RecordingStudioApi::ApiClient"]

    payload = RecordingStudioAccessible::AccessCreationContext.allow do
      result = RecordingStudioApi::Services::ProvisionApiClient.call(
        access_point_recording: access_recording.parent_recording || access_recording.root_recording,
        manager_actor: @admin,
        role: access_recording.recordable.role,
        name: "#{name}-#{SecureRandom.hex(4)}"
      )
      raise result.error unless result.success?

      result.value
    end

    token_result = RecordingStudioApi::Services::IssueOauthAccessToken.call(
      grant_type: "client_credentials",
      client_id: payload.fetch(:credential).oauth_client_id,
      client_secret: payload.fetch(:token)
    )
    raise token_result.error unless token_result.success?

    token_result.value.fetch(:access_token)
  ensure
    RecordingStudioAccessible.configuration.access_actor_types = previous_types
  end

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end
end
