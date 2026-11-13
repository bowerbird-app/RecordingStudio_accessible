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

  test "grant_access accepts a custom declared role" do
    Folder.accessible_roles :view, :download

    granted = RecordingStudioAccessible::Api::GrantAccess.call(
      admin_context(@folder, actor_id: @viewer.id.to_s, actor_type: "User", role: "download")
    )

    assert_equal false, granted.fetch(:invited)
    assert_equal "download", granted.fetch(:role)
    assert RecordingStudioAccessible.authorized_for_role?(
      actor: @viewer, recording: @folder, role: :download
    )
  ensure
    Folder.remove_instance_variable(:@accessible_role_set) if Folder.instance_variable_defined?(:@accessible_role_set)
  end

  test "admin can list grant update and revoke access" do
    listed = RecordingStudioAccessible::Api::ListAccess.call(admin_context(@root))
    emails = listed.fetch(:grants)
                   .select { |row| row.fetch(:status) == "granted" }
                   .map { |row| row.fetch(:actor).fetch(:label) }
    assert_includes emails, @admin.email
    assert_includes emails, @editor.email
    listed.fetch(:grants).each do |row|
      refute row.fetch(:inherited)
      assert_equal "granted", row.fetch(:status)
    end

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

  test "list_access includes pending invitations" do
    RecordingStudioAccessible.invite_access(
      recording: @root,
      email: "pending-invite@example.com",
      role: :view,
      manager_actor: @admin
    )

    listed = RecordingStudioAccessible::Api::ListAccess.call(admin_context(@root))
    pending = listed.fetch(:grants).find { |row| row[:status] == "pending" }

    assert_equal "pending-invite@example.com", pending.fetch(:email)
    assert_equal "view", pending.fetch(:role)
    assert_equal false, pending.fetch(:inherited)
    assert_equal @root.id, pending.fetch(:source_recording).fetch(:id)
    refute pending.key?(:actor)
    assert RecordingStudioAccessible::AccessInvitation.exists?(email: "pending-invite@example.com")
  end

  test "list_access marks expired unclosed invitations" do
    RecordingStudioAccessible.invite_access(
      recording: @root,
      email: "expired-invite@example.com",
      role: :edit,
      manager_actor: @admin
    )
    RecordingStudioAccessible::AccessInvitation.find_by!(email: "expired-invite@example.com")
                                 .update!(expires_at: 1.hour.ago)

    listed = RecordingStudioAccessible::Api::ListAccess.call(admin_context(@root))
    expired = listed.fetch(:grants).find { |row| row[:email] == "expired-invite@example.com" }

    assert_equal "expired", expired.fetch(:status)
    assert_equal "edit", expired.fetch(:role)
  end

  test "list_access omits accepted invitations" do
    RecordingStudioAccessible.invite_access(
      recording: @root,
      email: "will-accept@example.com",
      role: :view,
      manager_actor: @admin
    )
    invitation = RecordingStudioAccessible::AccessInvitation.find_by!(email: "will-accept@example.com")
    accepted = create_user("will-accept@example.com")
    result = RecordingStudioAccessible.accept_access_invitation(invitation: invitation, actor: accepted)
    assert result.success?

    listed = RecordingStudioAccessible::Api::ListAccess.call(admin_context(@root))
    emails = listed.fetch(:grants).filter_map { |row| row[:email] }

    refute_includes emails, "will-accept@example.com"
    assert listed.fetch(:grants).any? { |row| row.dig(:actor, :id) == accepted.id }
  end

  test "list_access pending invitations stay on their recording" do
    RecordingStudioAccessible.invite_access(
      recording: @root,
      email: "root-invite@example.com",
      role: :view,
      manager_actor: @admin
    )
    RecordingStudioAccessible.invite_access(
      recording: @folder,
      email: "folder-invite@example.com",
      role: :view,
      manager_actor: @admin
    )

    listed = RecordingStudioAccessible::Api::ListAccess.call(admin_context(@folder))
    emails = listed.fetch(:grants).filter_map { |row| row[:email] }

    assert_includes emails, "folder-invite@example.com"
    refute_includes emails, "root-invite@example.com"
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

  test "grant_access refused by the host hook is invalid input not a 500" do
    previous = RecordingStudioAccessible.configuration.before_access_grant
    RecordingStudioAccessible.configuration.before_access_grant = lambda do |_context|
      raise RecordingStudioAccessible::GrantRefused.new("You've filled every seat.")
    end

    error = assert_raises(invalid_input_error_class) do
      RecordingStudioAccessible::Api::GrantAccess.call(
        admin_context(@root, actor_id: @viewer.id.to_s, actor_type: "User", role: "view")
      )
    end
    assert_equal "You've filled every seat.", error.message
    assert_equal ["You've filled every seat."], error.details
    refute RecordingStudioAccessible.authorized?(actor: @viewer, recording: @root, role: :view)
  ensure
    RecordingStudioAccessible.configuration.before_access_grant = previous
  end

  test "grant_access refusal includes redirect_to in error details" do
    previous = RecordingStudioAccessible.configuration.before_access_grant
    RecordingStudioAccessible.configuration.before_access_grant = lambda do |_context|
      raise RecordingStudioAccessible::GrantRefused.new(
        "You've filled every seat.",
        redirect_to: "/plans"
      )
    end

    error = assert_raises(invalid_input_error_class) do
      RecordingStudioAccessible::Api::GrantAccess.call(
        admin_context(@root, actor_id: @viewer.id.to_s, actor_type: "User", role: "view")
      )
    end
    assert_equal "You've filled every seat.", error.message
    assert_includes error.details, { redirect_to: "/plans" }
    refute RecordingStudioAccessible.authorized?(actor: @viewer, recording: @root, role: :view)
  ensure
    RecordingStudioAccessible.configuration.before_access_grant = previous
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
    assert_equal "Add another admin before changing the last admin's role.", error.message
    assert_equal :admin, RecordingStudioAccessible.role_for(actor: only, recording: root)
  end

  test "access action 200 schemas include the returned payload keys" do
    grant = schema_for(:grant_access)
    list = schema_for(:list_access)
    revoke = schema_for(:revoke_access)
    update = schema_for(:update_access)

    %w[invited inherited role effective_role actor source_recording notice email].each do |key|
      assert_includes schema_property_names(grant), key
    end
    %w[grants inherited role effective_role actor source_recording status email].each do |key|
      assert_includes schema_property_names(list), key
    end
    %w[revoked actor id type label].each do |key|
      assert_includes schema_property_names(revoke), key
    end
    %w[invited inherited role effective_role actor source_recording].each do |key|
      assert_includes schema_property_names(update), key
    end
  end

  test "openapi override changes one type and leaves generic copy on another" do
    RecordingStudioAccessible::Api.override_openapi(
      type: "Folder",
      action: :grant_access,
      title: "Folder - Grant Access",
      description: "Folder-only grant copy."
    )

    folder = RecordingStudioAccessible::Api.openapi_for(:grant_access, type: "Folder")
    workspace = RecordingStudioAccessible::Api.openapi_for(:grant_access, type: "Workspace")

    assert_equal "Folder - Grant Access", folder.fetch(:title)
    assert_equal "Folder-only grant copy.", folder.fetch(:description)
    assert_equal RecordingStudioAccessible::Api::GRANT_ACCESS_DESCRIPTION, workspace.fetch(:description)
    refute workspace.key?(:title)
  ensure
    RecordingStudioAccessible::Api::OpenapiOverrides.reset!
  end

  test "inherited rows appear in list_access and cannot be updated or revoked" do
    listed = RecordingStudioAccessible::Api::ListAccess.call(admin_context(@folder))
    inherited = listed.fetch(:grants)
                      .select { |row| row.fetch(:status) == "granted" }
                      .find { |row| row.fetch(:actor).fetch(:id) == @editor.id }

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

  test "grant_access defaults actor_type to User when User is allowed" do
    granted = RecordingStudioAccessible::Api::GrantAccess.call(
      admin_context(@root, actor_id: @viewer.id.to_s, role: "view")
    )

    assert_equal false, granted.fetch(:invited)
    assert_equal "view", granted.fetch(:role)
    assert_equal @viewer.id, granted.fetch(:actor).fetch(:id)
    assert_equal "User", granted.fetch(:actor).fetch(:type)
    assert RecordingStudioAccessible.authorized?(actor: @viewer, recording: @root, role: :view)
  end

  test "grant_access still requires actor_type when User is not allowed" do
    previous = RecordingStudioAccessible.configuration.access_actor_types
    RecordingStudioAccessible.configuration.access_actor_types = ["Workspace"]

    error = assert_raises(invalid_input_error_class) do
      RecordingStudioAccessible::Api::GrantAccess.call(
        admin_context(@root, actor_id: @viewer.id.to_s, role: "view")
      )
    end
    assert_equal "Actor type is required", error.message
    refute RecordingStudioAccessible.authorized?(actor: @viewer, recording: @root, role: :view)
  ensure
    RecordingStudioAccessible.configuration.access_actor_types = previous
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

  def schema_for(action)
    RecordingStudioAccessible::Api.openapi_for(action).dig(:responses, "200", :content, "application/json", :schema)
  end

  def schema_property_names(node)
    return [] if node.nil?

    names = []
    if node.is_a?(Hash)
      properties = node[:properties] || node["properties"]
      if properties.is_a?(Hash)
        names.concat(properties.keys.map(&:to_s))
        properties.each_value { |child| names.concat(schema_property_names(child)) }
      end
      names.concat(schema_property_names(node[:items] || node["items"]))
      Array(node[:oneOf] || node["oneOf"]).each { |child| names.concat(schema_property_names(child)) }
    end
    names.uniq
  end

  def api_error_class(name, fallback)
    return fallback unless defined?(RecordingStudioApi)
    return fallback unless RecordingStudioApi.const_defined?(name, false)

    RecordingStudioApi.const_get(name, false)
  end
end
