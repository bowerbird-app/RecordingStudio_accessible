# frozen_string_literal: true

require_relative "../test_helper"

class AccessManagementCopyTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.find_by(email: "admin@admin.com") ||
             User.create!(email: "admin@admin.com", password: "Password", password_confirmation: "Password")
    @editor = User.find_by(email: "copy-editor@example.com") ||
              User.create!(email: "copy-editor@example.com", password: "Password", password_confirmation: "Password")
    @teams = Workspace.create!(name: "Copy Pack Teams")
    @other = Workspace.create!(name: "Copy Pack Other")
    @teams_recording = create_root_recording(@teams)
    @other_recording = create_root_recording(@other)
    assert RecordingStudioAccessible.bootstrap_owner_access!(recording: @teams_recording, actor: @admin).success?
    assert RecordingStudioAccessible.bootstrap_owner_access!(recording: @other_recording, actor: @admin).success?
    create_direct_access_recording(actor: @editor, role: :edit, parent_recording: @teams_recording)
    @previous_copy = RecordingStudioAccessible.configuration.access_management_copy
  end

  teardown do
    RecordingStudioAccessible.configuration.access_management_copy = @previous_copy
  end

  test "default config renders the current manage access copy" do
    RecordingStudioAccessible.configuration.access_management_copy = nil
    sign_in @admin

    get accesses_path(@teams_recording)

    assert_response :success
    assert_select "title", text: "Manage access"
    assert_select "h1", text: "Manage access"
    assert_includes @response.body, "+ Access"
    assert_includes @response.body, "Access requests"
  end

  test "a scope for one recording retitles that recording only" do
    RecordingStudioAccessible.configuration.access_management_copy = lambda do |recording:, **|
      next unless recording.id == @teams_recording.id

      { scope: "featured_in.teams" }
    end
    sign_in @admin

    get accesses_path(@teams_recording), params: { title: "Hacked" }

    assert_response :success
    assert_select "title", text: "Teams"
    assert_select "h1", text: "Teams"
    assert_select "meta[property='og:title'][content='Teams']"
    assert_includes @response.body, "+ Teammate"
    assert_includes @response.body, "Join requests"
    refute_includes @response.body, ">Manage access<"

    get accesses_path(@other_recording)

    assert_response :success
    assert_select "title", text: "Manage access"
    assert_select "h1", text: "Manage access"
    assert_includes @response.body, "+ Access"
    assert_includes @response.body, "Access requests"
    refute_includes @response.body, ">Teams<"

    get "#{accesses_path(@teams_recording)}/new"
    assert_response :success
    assert_select "title", text: "Add a teammate"
    assert_select "h1", text: "Add a teammate"

    access_id = RecordingStudioAccessible::DirectAccessQuery.access_recordings_for(@teams_recording).find do |recording|
      recording.recordable.actor == @editor
    end.id
    get "#{accesses_path(@teams_recording)}/#{access_id}/edit"
    assert_response :success
    assert_select "title", text: "Change team access"
    assert_select "h1", text: "Change team access"

    get recording_studio_accessible.recording_access_requests_path(@teams_recording)
    assert_response :success
    assert_select "title", text: "Join requests"
    assert_select "h1", text: "Join requests"
  end

  test "a partial host scope falls back key by key" do
    I18n.backend.store_translations(:en, { featured_in: { partial_teams: { manage: { title: "Crew" } } } })
    RecordingStudioAccessible.configuration.access_management_copy = lambda do |recording:, **|
      next unless recording.id == @teams_recording.id

      { scope: "featured_in.partial_teams" }
    end
    sign_in @admin

    get accesses_path(@teams_recording)

    assert_response :success
    assert_select "h1", text: "Crew"
    assert_includes @response.body, "+ Access"
    assert_includes @response.body, "Access requests"
  end

  test "a raising callable keeps the default copy" do
    RecordingStudioAccessible.configuration.access_management_copy = ->(**) { raise "boom" }
    sign_in @admin

    get accesses_path(@teams_recording)

    assert_response :success
    assert_select "h1", text: "Manage access"
    assert_includes @response.body, "+ Access"
  end

  test "retitled pages still allow admins and deny non-admins" do
    RecordingStudioAccessible.configuration.access_management_copy = lambda do |recording:, **|
      next unless recording.id == @teams_recording.id

      { scope: "featured_in.teams" }
    end

    sign_in @admin
    get accesses_path(@teams_recording)
    assert_response :success
    assert_select "h1", text: "Teams"

    sign_in @editor
    get accesses_path(@teams_recording)
    assert_response :forbidden
  end

  test "dummy teams workspace uses the featured_in teams scope" do
    teams = Workspace.find_or_create_by!(name: "Teams")
    recording = create_root_recording(teams)
    unless RecordingStudioAccessible.authorized?(actor: @admin, recording: recording, role: :admin)
      create_direct_access_recording(actor: @admin, role: :admin, parent_recording: recording)
    end
    sign_in @admin

    get accesses_path(recording)

    assert_response :success
    assert_select "h1", text: "Teams"
  end

  private

  def accesses_path(recording)
    "/recording_studio_accessible/recordings/#{recording.id}/accesses"
  end
end
