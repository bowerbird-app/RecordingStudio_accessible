require_relative "../test_helper"

class ThroughAuthorizationTest < ActiveSupport::TestCase
  setup do
    @original_authorize_actor_through = RecordingStudioAccessible.configuration.authorize_actor_through

    @user = create_user("through-user@example.com")
    @other_user = create_user("through-other@example.com")
    @through_workspace = Workspace.create!(name: "Through Workspace")
    @target_workspace = Workspace.create!(name: "Shared Message Group")
    @target_recording = create_root_recording(@target_workspace)
  end

  teardown do
    RecordingStudioAccessible.configuration.authorize_actor_through = @original_authorize_actor_through
  end

  test "existing direct actor access remains unchanged" do
    create_direct_access_recording(actor: @user, role: :view, parent_recording: @target_recording)

    assert RecordingStudioAccessible.authorized?(actor: @user, recording: @target_recording, role: :view)
    assert_equal :view, RecordingStudioAccessible.role_for(actor: @user, recording: @target_recording)
  end

  test "exact checks do not use configured through actors" do
    create_direct_access_recording(actor: @through_workspace, role: :view, parent_recording: @target_recording)
    allow_user_through_workspace!

    refute RecordingStudioAccessible.authorized?(actor: @user, recording: @target_recording, role: :view)
    assert_nil RecordingStudioAccessible.role_for(actor: @user, recording: @target_recording)
    assert_empty RecordingStudioAccessible.root_recordings_for(actor: @user)
  end

  test "default through authorization only allows the same actor" do
    create_direct_access_recording(actor: @user, role: :view, parent_recording: @target_recording)
    create_direct_access_recording(actor: @through_workspace, role: :view, parent_recording: @target_recording)

    assert_equal RecordingStudioAccessible.authorized?(actor: @user, recording: @target_recording, role: :view),
                 RecordingStudioAccessible.authorized_through?(
                   actor: @user,
                   through: @user,
                   recording: @target_recording,
                   role: :view
                 )
    refute RecordingStudioAccessible.authorized_through?(
      actor: @user,
      through: @through_workspace,
      recording: @target_recording,
      role: :view
    )
  end

  test "configured through authorization works" do
    create_direct_access_recording(actor: @through_workspace, role: :edit, parent_recording: @target_recording)
    allow_user_through_workspace!

    assert RecordingStudioAccessible.authorized_through?(
      actor: @user,
      through: @through_workspace,
      recording: @target_recording,
      role: :edit
    )
  end

  test "through actor must have the required role" do
    create_direct_access_recording(actor: @through_workspace, role: :view, parent_recording: @target_recording)
    allow_user_through_workspace!

    refute RecordingStudioAccessible.authorized_through?(
      actor: @user,
      through: @through_workspace,
      recording: @target_recording,
      role: :edit
    )
  end

  test "role_through returns the through actor role when through is allowed" do
    create_direct_access_recording(actor: @through_workspace, role: :edit, parent_recording: @target_recording)
    allow_user_through_workspace!

    assert_equal RecordingStudioAccessible.role_for(actor: @through_workspace, recording: @target_recording),
                 RecordingStudioAccessible.role_through(
                   actor: @user,
                   through: @through_workspace,
                   recording: @target_recording
                 )
  end

  test "role_through returns nil when through is not allowed" do
    create_direct_access_recording(actor: @through_workspace, role: :edit, parent_recording: @target_recording)

    assert_nil RecordingStudioAccessible.role_through(
      actor: @user,
      through: @through_workspace,
      recording: @target_recording
    )
  end

  test "hook failure fails closed" do
    create_direct_access_recording(actor: @through_workspace, role: :edit, parent_recording: @target_recording)
    RecordingStudioAccessible.configuration.authorize_actor_through = ->(**) { raise "boom" }

    refute RecordingStudioAccessible.authorized_through?(
      actor: @user,
      through: @through_workspace,
      recording: @target_recording,
      role: :edit
    )
    assert_nil RecordingStudioAccessible.role_through(
      actor: @user,
      through: @through_workspace,
      recording: @target_recording
    )
  end

  test "nil through authorization inputs fail closed before invoking hook" do
    create_direct_access_recording(actor: @through_workspace, role: :edit, parent_recording: @target_recording)
    RecordingStudioAccessible.configuration.authorize_actor_through = ->(**) { true }

    refute RecordingStudioAccessible.authorized_through?(
      actor: nil,
      through: @through_workspace,
      recording: @target_recording,
      role: :edit
    )
    assert_nil RecordingStudioAccessible.role_through(
      actor: nil,
      through: @through_workspace,
      recording: @target_recording
    )
    refute RecordingStudioAccessible.authorized_through?(
      actor: @user,
      through: nil,
      recording: @target_recording,
      role: :edit
    )
    assert_nil RecordingStudioAccessible.role_through(
      actor: @user,
      through: nil,
      recording: @target_recording
    )
  end

  test "nil role authorization inputs fail closed" do
    create_direct_access_recording(actor: @through_workspace, role: :edit, parent_recording: @target_recording)
    allow_user_through_workspace!

    refute RecordingStudioAccessible.authorized?(
      actor: @through_workspace,
      recording: @target_recording,
      role: nil
    )
    refute RecordingStudioAccessible.authorized_through?(
      actor: @user,
      through: @through_workspace,
      recording: @target_recording,
      role: nil
    )
  end

  test "access recordings for actor remains exact" do
    workspace_access = create_direct_access_recording(
      actor: @through_workspace,
      role: :view,
      parent_recording: @target_recording
    )

    assert_empty RecordingStudioAccessible.access_recordings_for_actor(recording: @target_recording, actor: @user)
    assert_equal [ workspace_access.id ],
                 RecordingStudioAccessible.access_recordings_for_actor(
                   recording: @target_recording,
                   actor: @through_workspace
                 ).pluck(:id)
  end

  test "inherited access still works for the through actor" do
    folder = Folder.create!(workspace: @target_workspace, name: "Shared Folder", summary: "Folder", position: 0)
    folder_recording = create_child_recording(recordable: folder, parent_recording: @target_recording)
    page = Page.create!(folder: folder, title: "Shared Page", summary: "Page", position: 0)
    page_recording = create_child_recording(recordable: page, parent_recording: folder_recording)
    create_direct_access_recording(actor: @through_workspace, role: :view, parent_recording: @target_recording)
    allow_user_through_workspace!

    assert RecordingStudioAccessible.authorized_through?(
      actor: @user,
      through: @through_workspace,
      recording: page_recording,
      role: :view
    )
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def allow_user_through_workspace!
    RecordingStudioAccessible.configuration.authorize_actor_through = lambda do |actor:, through:, **|
      actor == @user && through == @through_workspace
    end
  end
end
