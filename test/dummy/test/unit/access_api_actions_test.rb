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

  test "admin can list grant update and revoke access" do
    listed = RecordingStudioAccessible::Api::ListAccess.call(admin_context(@root))
    emails = listed.fetch(:grants).map { |row| row.fetch(:actor).fetch(:label) }
    assert_includes emails, @admin.email
    assert_includes emails, @editor.email
    listed.fetch(:grants).each { |row| refute row.fetch(:inherited) }

    granted = RecordingStudioAccessible::Api::GrantAccess.call(
      admin_context(@root, actor_id: @viewer.id.to_s, actor_type: "User", role: "view")
    )
    assert_equal false, granted.fetch(:invited)
    assert_equal "view", granted.fetch(:role)
    assert_equal @viewer.id, granted.fetch(:actor).fetch(:id)
    assert RecordingStudioAccessible.authorized?(actor: @viewer, recording: @root, role: :view)

    updated = RecordingStudioAccessible::Api::UpdateAccess.call(
      admin_context(@root, actor_id: @viewer.id.to_s, actor_type: "User", role: "edit")
    )
    assert_equal "edit", updated.fetch(:role)
    assert_equal :edit, RecordingStudioAccessible.role_for(actor: @viewer, recording: @root)

    revoked = RecordingStudioAccessible::Api::RevokeAccess.call(
      admin_context(@root, actor_id: @viewer.id.to_s, actor_type: "User")
    )
    assert_equal true, revoked.fetch(:revoked)
    refute RecordingStudioAccessible.authorized?(actor: @viewer, recording: @root, role: :view)
  end

  test "list_access omits pending invitations" do
    RecordingStudioAccessible.invite_access(
      recording: @root,
      email: "pending-invite@example.com",
      role: :view,
      manager_actor: @admin
    )

    listed = RecordingStudioAccessible::Api::ListAccess.call(admin_context(@root))
    labels = listed.fetch(:grants).filter_map { |row| row.dig(:actor, :label) }

    refute_includes labels, "pending-invite@example.com"
    assert RecordingStudioAccessible::AccessInvitation.exists?(email: "pending-invite@example.com")
  end

  test "non-admin is denied" do
    error = assert_raises(authorization_error_class) do
      RecordingStudioAccessible::Api::ListAccess.call(actor_context(@editor, @root))
    end
    assert_equal "Not authorized to manage access", error.message

    error = assert_raises(authorization_error_class) do
      RecordingStudioAccessible::Api::GrantAccess.call(
        actor_context(@editor, @root, actor_id: @viewer.id.to_s, actor_type: "User", role: "view")
      )
    end
    assert_equal "Not authorized to manage access", error.message
  end

  test "admin of one workspace cannot list or grant on another" do
    other_root = create_root_recording(Workspace.create!(name: "Other API Workspace"))
    outsider = create_user("other-api-admin@example.com")
    create_direct_access_recording(actor: outsider, role: :admin, parent_recording: other_root)

    error = assert_raises(authorization_error_class) do
      RecordingStudioAccessible::Api::ListAccess.call(admin_context(other_root))
    end
    assert_equal "Not authorized to manage access", error.message

    error = assert_raises(authorization_error_class) do
      RecordingStudioAccessible::Api::GrantAccess.call(
        admin_context(other_root, email: "cross-grant@example.com", role: "view")
      )
    end
    assert_equal "Not authorized to manage access", error.message
  end

  test "cannot update or revoke a grant that lives on another recording" do
    other_root = create_root_recording(Workspace.create!(name: "IDOR Workspace"))
    create_direct_access_recording(actor: @admin, role: :admin, parent_recording: other_root)
    stranger = create_user("idor-actor@example.com")
    create_direct_access_recording(actor: stranger, role: :edit, parent_recording: other_root)

    error = assert_raises(invalid_input_error_class) do
      RecordingStudioAccessible::Api::UpdateAccess.call(
        admin_context(@root, actor_id: stranger.id.to_s, actor_type: "User", role: "view")
      )
    end
    assert_equal "Access recording is invalid", error.message
    assert_equal :edit, RecordingStudioAccessible.role_for(actor: stranger, recording: other_root)

    error = assert_raises(invalid_input_error_class) do
      RecordingStudioAccessible::Api::RevokeAccess.call(
        admin_context(@root, actor_id: stranger.id.to_s, actor_type: "User")
      )
    end
    assert_equal "Access recording is invalid", error.message
    assert RecordingStudioAccessible.authorized?(actor: stranger, recording: other_root, role: :edit)
  end

  test "role ceiling blocks granting above the manager role" do
    previous = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }

    error = assert_raises(invalid_input_error_class) do
      RecordingStudioAccessible::Api::GrantAccess.call(
        actor_context(@editor, @root, actor_id: @viewer.id.to_s, actor_type: "User", role: "admin")
      )
    end
    assert_equal "You can only grant a role you already hold.", error.message
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = previous
  end

  test "invite role ceiling blocks inviting above the manager role" do
    previous = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }

    error = assert_raises(invalid_input_error_class) do
      RecordingStudioAccessible::Api::GrantAccess.call(
        actor_context(@editor, @root, email: "ceiling-invite@example.com", role: "admin")
      )
    end
    assert_equal "You can only grant a role you already hold.", error.message
    assert_equal 0, RecordingStudioAccessible::AccessInvitation.where(email: "ceiling-invite@example.com").count
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = previous
  end

  test "update_access cannot self-escalate past the manager role" do
    previous = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }

    error = assert_raises(invalid_input_error_class) do
      RecordingStudioAccessible::Api::UpdateAccess.call(
        actor_context(@editor, @root, actor_id: @editor.id.to_s, actor_type: "User", role: "admin")
      )
    end
    assert_equal "You can only grant a role you already hold.", error.message
    assert_equal :edit, RecordingStudioAccessible.role_for(actor: @editor, recording: @root)
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = previous
  end

  test "revoke_access of the last admin is 422 with last_admin copy" do
    error = assert_raises(invalid_input_error_class) do
      RecordingStudioAccessible::Api::RevokeAccess.call(
        admin_context(@root, actor_id: @admin.id.to_s, actor_type: "User")
      )
    end
    assert_equal "Add another admin before removing the last one.", error.message
    assert RecordingStudioAccessible.authorized?(actor: @admin, recording: @root, role: :admin)
  end

  test "update_access downgrading the last admin is 422 with last_admin copy" do
    only = create_user("api-only-admin@example.com")
    workspace = Workspace.create!(name: "API Last Admin Workspace")
    root = create_root_recording(workspace)
    create_direct_access_recording(actor: only, role: :admin, parent_recording: root)

    error = assert_raises(invalid_input_error_class) do
      RecordingStudioAccessible::Api::UpdateAccess.call(
        actor_context(only, root, actor_id: only.id.to_s, actor_type: "User", role: "view")
      )
    end
    assert_equal "Add another admin before removing the last one.", error.message
    assert_equal :admin, RecordingStudioAccessible.role_for(actor: only, recording: root)
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
        admin_context(@folder, actor_id: @editor.id.to_s, actor_type: "User", role: "view")
      )
    end
    assert_includes error.message, "API Access Workspace"
    refute_includes error.details.join, "source_id="
    refute_includes error.details.join, "source_type="

    error = assert_raises(invalid_input_error_class) do
      RecordingStudioAccessible::Api::RevokeAccess.call(
        admin_context(@folder, actor_id: @editor.id.to_s, actor_type: "User")
      )
    end
    assert_includes error.message, "API Access Workspace"
    refute_includes error.details.join, "source_id="
    assert RecordingStudioAccessible.authorized?(actor: @editor, recording: @folder, role: :edit)
  end

  test "shared root list_access returns not found" do
    message_root_recording = create_root_recording(MessageRoot.create!(name: "API Shared List"))
    previous = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }

    error = assert_raises(not_found_error_class) do
      RecordingStudioAccessible::Api::ListAccess.call(admin_context(message_root_recording))
    end
    assert_equal "Direct access is not enabled for this recording", error.message
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = previous
  end

  test "shared root cannot be a grant target" do
    message_root_recording = create_root_recording(MessageRoot.create!(name: "API Shared Messages"))
    previous = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }

    error = assert_raises(not_found_error_class) do
      RecordingStudioAccessible::Api::GrantAccess.call(
        admin_context(message_root_recording, actor_id: @viewer.id.to_s, actor_type: "User", role: "view")
      )
    end
    assert_equal "Direct access is not enabled for this recording", error.message
  ensure
    RecordingStudioAccessible.configuration.access_management_authorizer = previous
  end

  test "shared root update and revoke return not found" do
    message_root_recording = create_root_recording(MessageRoot.create!(name: "API Shared Update"))
    previous = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }

    error = assert_raises(not_found_error_class) do
      RecordingStudioAccessible::Api::UpdateAccess.call(
        admin_context(message_root_recording, actor_id: @editor.id.to_s, actor_type: "User", role: "view")
      )
    end
    assert_equal "Direct access is not enabled for this recording", error.message

    error = assert_raises(not_found_error_class) do
      RecordingStudioAccessible::Api::RevokeAccess.call(
        admin_context(message_root_recording, actor_id: @editor.id.to_s, actor_type: "User")
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

  test "invalid email is rejected" do
    error = assert_raises(invalid_input_error_class) do
      RecordingStudioAccessible::Api::GrantAccess.call(
        admin_context(@root, email: "not-an-email", role: "view")
      )
    end
    assert_equal "Email is invalid", error.message
  end

  test "actor_id cannot mix with email" do
    error = assert_raises(invalid_input_error_class) do
      RecordingStudioAccessible::Api::GrantAccess.call(
        admin_context(@root, actor_id: @viewer.id.to_s, actor_type: "User", email: @viewer.email, role: "view")
      )
    end
    assert_equal "Give an actor id or an email, not both.", error.message
    refute RecordingStudioAccessible.authorized?(actor: @viewer, recording: @root, role: :view)
  end

  test "actor_id grants require actor_type" do
    error = assert_raises(invalid_input_error_class) do
      RecordingStudioAccessible::Api::GrantAccess.call(
        admin_context(@root, actor_id: @viewer.id.to_s, role: "view")
      )
    end
    assert_equal "Actor type is required", error.message
  end

  test "actor_type is allowlisted before constantize" do
    error = assert_raises(invalid_input_error_class) do
      RecordingStudioAccessible::Api::GrantAccess.call(
        admin_context(@root, actor_id: @viewer.id.to_s, actor_type: "Kernel", role: "view")
      )
    end
    assert_equal "Actor type is not allowed for access", error.message
  end

  test "update_access does not default to User when User is not allowed" do
    previous = RecordingStudioAccessible.configuration.access_actor_types
    RecordingStudioAccessible.configuration.access_actor_types = ["Workspace"]

    error = assert_raises(invalid_input_error_class) do
      RecordingStudioAccessible::Api::UpdateAccess.call(
        admin_context(@root, actor_id: @editor.id.to_s, role: "view")
      )
    end
    assert_equal "Actor type is required", error.message
    assert_equal :edit, RecordingStudioAccessible.role_for(actor: @editor, recording: @root)
  ensure
    RecordingStudioAccessible.configuration.access_actor_types = previous
  end

  test "workspace actor_id grant cannot create through-admin" do
    other = Workspace.create!(name: "Through Workspace")
    other_root = create_root_recording(other)
    member = create_user("through-member@example.com")
    create_direct_access_recording(actor: member, role: :view, parent_recording: other_root)

    error = assert_raises(invalid_input_error_class) do
      RecordingStudioAccessible::Api::GrantAccess.call(
        admin_context(@root, actor_id: other.id.to_s, actor_type: "Workspace", role: "admin")
      )
    end
    assert_equal "Actor type is not allowed for access", error.message
    refute RecordingStudioAccessible.authorized?(actor: other, recording: @root, role: :admin)
    refute RecordingStudioAccessible.authorized_through?(
      actor: member,
      through: other,
      recording: @root,
      role: :admin
    )
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
    api_error_class(:AuthorizationError, RecordingStudioAccessible::Api::AuthorizationError)
  end

  def invalid_input_error_class
    api_error_class(:InvalidActionInputError, RecordingStudioAccessible::Api::InvalidInputError)
  end

  def not_found_error_class
    api_error_class(:NotFoundError, RecordingStudioAccessible::Api::NotFoundError)
  end

  def api_error_class(name, fallback)
    return fallback unless defined?(RecordingStudioApi)
    return fallback unless RecordingStudioApi.const_defined?(name, false)

    RecordingStudioApi.const_get(name, false)
  end
end
