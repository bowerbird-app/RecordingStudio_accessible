# frozen_string_literal: true

require "test_helper"
require "recording_studio_accessible/api"

class AccessApiActionsTest < ActiveSupport::TestCase
  AccessGrant = Struct.new(:actor)
  Context = Struct.new(:recording, :access_grant, :params, keyword_init: true)

  setup do
    ActionMailer::Base.deliveries.clear
    @admin = create_user("api-admin@example.com")
    @editor = create_user("api-editor@example.com")
    @viewer = create_user("api-viewer@example.com")
    @workspace = Workspace.create!(name: "API Access Workspace")
    @root = create_root_recording(@workspace)
    folder = Folder.create!(workspace: @workspace, name: "API Folder", summary: "Folder", position: 0)
    @folder = create_child_recording(recordable: folder, parent_recording: @root)

    create_direct_access_recording(actor: @admin, role: :admin, parent_recording: @root)
    create_direct_access_recording(actor: @editor, role: :edit, parent_recording: @root)
  end

  test "dummy type APIs list access actions for current Recording Studio API" do
    source = File.read(Rails.root.join("config/initializers/recording_studio_api.rb"))

    %w[list_access grant_access update_access revoke_access Workspace Folder MessageGroup].each do |token|
      assert_includes source, token
    end
  end

  test "admin can list grant update and revoke access" do
    listed = RecordingStudioAccessible::Api::ListAccess.call(admin_context(@root))
    emails = listed.fetch(:grants).map { |row| row.fetch(:actor).fetch(:label) }
    assert_includes emails, @admin.email
    assert_includes emails, @editor.email
    listed.fetch(:grants).each { |row| refute row.fetch(:inherited) }

    granted = RecordingStudioAccessible::Api::GrantAccess.call(
      admin_context(@root, actor_id: @viewer.id.to_s, role: "view")
    )
    assert_equal false, granted.fetch(:invited)
    assert_equal "view", granted.fetch(:role)
    assert_equal @viewer.id, granted.fetch(:actor).fetch(:id)
    assert RecordingStudioAccessible.authorized?(actor: @viewer, recording: @root, role: :view)

    updated = RecordingStudioAccessible::Api::UpdateAccess.call(
      admin_context(@root, actor_id: @viewer.id.to_s, role: "edit")
    )
    assert_equal "edit", updated.fetch(:role)
    assert_equal :edit, RecordingStudioAccessible.role_for(actor: @viewer, recording: @root)

    revoked = RecordingStudioAccessible::Api::RevokeAccess.call(
      admin_context(@root, actor_id: @viewer.id.to_s)
    )
    assert_equal true, revoked.fetch(:revoked)
    refute RecordingStudioAccessible.authorized?(actor: @viewer, recording: @root, role: :view)
  end

  test "non-admin is denied" do
    error = assert_raises(authorization_error_class) do
      RecordingStudioAccessible::Api::ListAccess.call(actor_context(@editor, @root))
    end
    assert_equal "Not authorized to manage access", error.message

    error = assert_raises(authorization_error_class) do
      RecordingStudioAccessible::Api::GrantAccess.call(
        actor_context(@editor, @root, actor_id: @viewer.id.to_s, role: "view")
      )
    end
    assert_equal "Not authorized to manage access", error.message
  end

  test "role ceiling blocks granting above the manager role" do
    previous = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }

    error = assert_raises(invalid_input_error_class) do
      RecordingStudioAccessible::Api::GrantAccess.call(
        actor_context(@editor, @root, actor_id: @viewer.id.to_s, role: "admin")
      )
    end
    assert_equal "You can only grant a role you already hold.", error.message
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = previous
  end

  test "inherited rows appear in list_access and cannot be updated or revoked" do
    listed = RecordingStudioAccessible::Api::ListAccess.call(admin_context(@folder))
    inherited = listed.fetch(:grants).find { |row| row.fetch(:actor).fetch(:id) == @editor.id }

    assert inherited.fetch(:inherited)
    assert_equal "edit", inherited.fetch(:role)
    assert_equal "edit", inherited.fetch(:effective_role)
    assert_equal @root.id, inherited.fetch(:source_recording).fetch(:id)
    refute_equal "RecordingStudio::Access", inherited.fetch(:source_recording).fetch(:type)

    error = assert_raises(invalid_input_error_class) do
      RecordingStudioAccessible::Api::UpdateAccess.call(
        admin_context(@folder, actor_id: @editor.id.to_s, role: "view")
      )
    end
    assert_includes error.message, "API Access Workspace"
    assert_includes error.details.join, @root.id.to_s

    error = assert_raises(invalid_input_error_class) do
      RecordingStudioAccessible::Api::RevokeAccess.call(
        admin_context(@folder, actor_id: @editor.id.to_s)
      )
    end
    assert_includes error.message, "API Access Workspace"
    assert RecordingStudioAccessible.authorized?(actor: @editor, recording: @folder, role: :edit)
  end

  test "shared root cannot be a grant target" do
    message_root = MessageRoot.create!(name: "API Shared Messages")
    message_root_recording = create_root_recording(message_root)
    previous = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }

    error = assert_raises(not_found_error_class) do
      RecordingStudioAccessible::Api::GrantAccess.call(
        admin_context(message_root_recording, actor_id: @viewer.id.to_s, role: "view")
      )
    end
    assert_equal "Direct access is not enabled for this recording", error.message
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = previous
  end

  test "email grant goes through invite" do
    result = RecordingStudioAccessible::Api::GrantAccess.call(
      admin_context(@root, email: "new-person@example.com", role: "view")
    )

    assert_equal true, result.fetch(:invited)
    assert_equal "new-person@example.com", result.fetch(:email)
    assert_equal 1, RecordingStudioAccessible::AccessInvitation.where(email: "new-person@example.com").count
  end

  test "existing email grants immediately through invite_access" do
    result = RecordingStudioAccessible::Api::GrantAccess.call(
      admin_context(@root, email: @viewer.email, role: "view")
    )

    assert_equal false, result.fetch(:invited)
    assert_equal @viewer.id, result.fetch(:actor).fetch(:id)
    assert RecordingStudioAccessible.authorized?(actor: @viewer, recording: @root, role: :view)
    assert_equal 0, RecordingStudioAccessible::AccessInvitation.where(email: @viewer.email).count
  end

  private

  def admin_context(recording, **params)
    actor_context(@admin, recording, **params)
  end

  def actor_context(actor, recording, **params)
    Context.new(recording: recording, access_grant: AccessGrant.new(actor), params: params)
  end

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def authorization_error_class
    RecordingStudioAccessible::Api::AuthorizationError
  end

  def invalid_input_error_class
    RecordingStudioAccessible::Api::InvalidInputError
  end

  def not_found_error_class
    RecordingStudioAccessible::Api::NotFoundError
  end
end
