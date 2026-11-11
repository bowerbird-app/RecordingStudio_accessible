# frozen_string_literal: true

require_relative "../test_helper"

class BeforeAccessGrantTest < ActiveSupport::TestCase
  setup do
    @manager = create_user("grant-hook-manager@example.com")
    @person = create_user("grant-hook-person@example.com")
    @workspace = Workspace.create!(name: "Grant Hook Workspace")
    @recording = create_root_recording(@workspace)
    create_direct_access_recording(actor: @manager, role: :admin, parent_recording: @recording)
    @previous_hook = RecordingStudioAccessible.configuration.before_access_grant
    @seen = []
  end

  teardown do
    RecordingStudioAccessible.configuration.before_access_grant = @previous_hook
  end

  test "nil hook leaves grant behaviour unchanged" do
    RecordingStudioAccessible.configuration.before_access_grant = nil

    result = RecordingStudioAccessible.grant_access(
      recording: @recording, actor: @person, role: :view, manager_actor: @manager
    )

    assert result.success?
    assert RecordingStudioAccessible.authorized?(actor: @person, recording: @recording, role: :view)
  end

  test "allowing hook sees grant source fields and writes the grant" do
    allow_hook

    result = RecordingStudioAccessible.grant_access(
      recording: @recording, actor: @person, role: :view, manager_actor: @manager
    )

    assert result.success?
    context = @seen.last
    assert_equal @person, context.actor
    assert_equal "User", context.actor_type
    assert_equal @person.id, context.actor_id
    assert_equal @recording, context.recording
    assert_equal "view", context.role
    assert_nil context.previous_role
    assert_equal :grant, context.source
    assert_equal @manager, context.granted_by
    assert context.frozen?
  end

  test "refusing hook raises GrantRefused and rolls back the Access recording" do
    refuse_hook("You've filled every seat.")

    assert_no_difference -> { RecordingStudio::Access.count } do
      error = assert_raises(RecordingStudioAccessible::GrantRefused) do
        RecordingStudioAccessible.grant_access(
          recording: @recording, actor: @person, role: :view, manager_actor: @manager
        )
      end

      assert_equal "You've filled every seat.", error.message
      assert_equal "/plans", error.redirect_to
    end
    refute RecordingStudioAccessible.authorized?(actor: @person, recording: @recording, role: :view)
  end

  test "refusing a role change leaves the previous role" do
    RecordingStudioAccessible.grant_access(
      recording: @recording, actor: @person, role: :view, manager_actor: @manager
    )
    refuse_hook("Every seat is taken.")
    access = RecordingStudioAccessible.access_recordings_for_actor(recording: @recording, actor: @person).first

    assert_raises(RecordingStudioAccessible::GrantRefused) do
      RecordingStudioAccessible.update_access(
        recording: @recording, access_recording: access, role: :edit, manager_actor: @manager
      )
    end
    assert_equal :role_change, @seen.last.source
    assert_equal "view", access.reload.recordable.role
  end

  test "role change source runs after a direct grant exists" do
    RecordingStudioAccessible.grant_access(
      recording: @recording, actor: @person, role: :view, manager_actor: @manager
    )
    allow_hook

    access = RecordingStudioAccessible.access_recordings_for_actor(recording: @recording, actor: @person).first
    result = RecordingStudioAccessible.update_access(
      recording: @recording, access_recording: access, role: :edit, manager_actor: @manager
    )

    assert result.success?
    context = @seen.last
    assert_equal :role_change, context.source
    assert_equal "view", context.previous_role
    assert_equal "edit", context.role
  end

  test "grant_access that changes role uses role_change" do
    RecordingStudioAccessible.grant_access(
      recording: @recording, actor: @person, role: :view, manager_actor: @manager
    )
    allow_hook

    RecordingStudioAccessible.grant_access(
      recording: @recording, actor: @person, role: :edit, manager_actor: @manager
    )

    assert_equal :role_change, @seen.last.source
    assert_equal "view", @seen.last.previous_role
  end

  test "same role grant does not call the hook" do
    RecordingStudioAccessible.grant_access(
      recording: @recording, actor: @person, role: :view, manager_actor: @manager
    )
    allow_hook

    RecordingStudioAccessible.grant_access(
      recording: @recording, actor: @person, role: :view, manager_actor: @manager
    )

    assert_empty @seen
  end

  test "invite creation uses invite source and stores no invitation when refused" do
    refuse_hook("You've filled every seat.")

    assert_no_difference -> { RecordingStudioAccessible::AccessInvitation.count } do
      assert_raises(RecordingStudioAccessible::GrantRefused) do
        RecordingStudioAccessible.invite_access(
          recording: @recording, email: "new-seat@example.com", role: :view, manager_actor: @manager
        )
      end
    end
    assert_equal :invite, @seen.last.source
    assert_nil @seen.last.actor
  end

  test "invite creation is allowed when the hook returns" do
    allow_hook

    result = RecordingStudioAccessible.invite_access(
      recording: @recording, email: "new-seat@example.com", role: :view, manager_actor: @manager
    )

    assert result.success?
    assert result.value.invited?
    assert_equal :invite, @seen.last.source
  end

  test "refusing invite acceptance writes no Access recording" do
    pending = RecordingStudioAccessible.invite_access(
      recording: @recording, email: "accept-seat@example.com", role: :view, manager_actor: @manager
    )
    invitation = RecordingStudioAccessible::AccessInvitation.find(pending.value.pending.id)
    invitee = create_user("accept-seat@example.com")
    refuse_hook("Every seat is taken.")

    assert_no_difference -> { RecordingStudio::Access.count } do
      assert_raises(RecordingStudioAccessible::GrantRefused) do
        RecordingStudioAccessible.accept_access_invitation(invitation: invitation, actor: invitee)
      end
    end
    assert_equal :invite_acceptance, @seen.last.source
    refute RecordingStudioAccessible.authorized?(actor: invitee, recording: @recording, role: :view)
  end

  test "invite acceptance uses invite_acceptance source" do
    pending = RecordingStudioAccessible.invite_access(
      recording: @recording, email: "accept-seat@example.com", role: :view, manager_actor: @manager
    )
    assert pending.value.invited?
    invitation = RecordingStudioAccessible::AccessInvitation.find(pending.value.pending.id)
    invitee = create_user("accept-seat@example.com")
    allow_hook

    result = RecordingStudioAccessible.accept_access_invitation(invitation: invitation, actor: invitee)

    assert result.success?
    assert_equal :invite_acceptance, @seen.last.source
    assert_equal invitee, @seen.last.actor
  end

  test "refusing access request approval leaves the request pending" do
    request = RecordingStudioAccessible.request_access(
      recording: @recording, actor: @person, role: :view
    ).value
    refuse_hook("Every seat is taken.")

    assert_raises(RecordingStudioAccessible::GrantRefused) do
      RecordingStudioAccessible.approve_access_request(
        request_recording: request, manager_actor: @manager, role: :view
      )
    end
    assert_equal :access_request, @seen.last.source
    assert_equal "pending", request.reload.recordable.status
    refute RecordingStudioAccessible.authorized?(actor: @person, recording: @recording, role: :view)
  end

  test "access request approval uses access_request source" do
    request = RecordingStudioAccessible.request_access(
      recording: @recording, actor: @person, role: :view
    ).value
    allow_hook

    result = RecordingStudioAccessible.approve_access_request(
      request_recording: request, manager_actor: @manager, role: :view
    )

    assert result.success?
    assert_equal :access_request, @seen.last.source
    assert_equal @person, @seen.last.actor
  end

  test "bootstrap does not call the hook" do
    workspace = Workspace.create!(name: "Bootstrap Hook Workspace")
    recording = create_root_recording(workspace)
    owner = create_user("bootstrap-hook-owner@example.com")
    refuse_hook("You've filled every seat.")

    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: owner)

    assert result.success?
    assert_empty @seen
    assert RecordingStudioAccessible.authorized?(actor: owner, recording: recording, role: :admin)
  end

  test "a Workspace actor grant shows that actor, not a member" do
    allow_hook

    result = RecordingStudioAccessible.grant_access(
      recording: @recording, actor: @workspace, role: :view, manager_actor: @manager
    )

    assert result.success?
    assert_equal @workspace, @seen.last.actor
    assert_equal "Workspace", @seen.last.actor_type
    assert_equal @workspace.id, @seen.last.actor_id
  end

  test "other errors still become unexpected failure copy" do
    RecordingStudioAccessible.configuration.before_access_grant = ->(_context) { raise "boom" }

    result = RecordingStudioAccessible.grant_access(
      recording: @recording, actor: @person, role: :view, manager_actor: @manager
    )

    assert result.failure?
    assert_equal "Something went wrong. Try again.", result.error
  end

  private

  def allow_hook
    RecordingStudioAccessible.configuration.before_access_grant = lambda do |context|
      @seen << context
    end
  end

  def refuse_hook(message)
    RecordingStudioAccessible.configuration.before_access_grant = lambda do |context|
      @seen << context
      raise RecordingStudioAccessible::GrantRefused.new(
        message,
        redirect_to: "/plans"
      )
    end
  end

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end
end
