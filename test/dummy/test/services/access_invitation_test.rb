# frozen_string_literal: true

require_relative "../test_helper"

class AccessInvitationTest < ActiveSupport::TestCase
  setup do
    ActionMailer::Base.deliveries.clear
    @manager = create_user("invite-manager@example.com")
    @workspace = Workspace.create!(name: "Invitation Workspace")
    @recording = create_root_recording(@workspace)
    bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(recording: @recording, actor: @manager)
    assert bootstrap.success?, bootstrap.error
  end

  test "existing actor grants immediately and creates no invitation" do
    user = create_user("exists@example.com")

    result = invite_email(" Exists@Example.com ")

    assert result.success?
    assert result.value.granted?
    assert_equal "Access granted.", result.value.notice
    assert_equal user, result.value.access_recording.recordable.actor
    assert_equal "view", result.value.access_recording.recordable.role
    assert_equal 0, RecordingStudioAccessible::AccessInvitation.count
    assert RecordingStudioAccessible.authorized?(actor: user, recording: @recording, role: :view)
    assert_equal :view, RecordingStudioAccessible.role_for(actor: user, recording: @recording)
    assert_equal "You were given access to Invitation Workspace", ActionMailer::Base.deliveries.last.subject
  end

  test "default invitation delivery hands off the acceptance mail" do
    result = invite_email("delivered@example.com")

    assert result.success?
    assert result.value.invited?
    assert_equal "Invitation sent.", result.value.notice
    delivery = ActionMailer::Base.deliveries.last
    refute_nil delivery
    assert_equal ["delivered@example.com"], delivery.to
    assert_includes delivery.body.encoded, "Accept the invitation"
    assert_match %r{access_invitations/[A-Za-z0-9_-]{20,}}, delivery.body.encoded
  end

  test "notifier failure keeps the invitation and does not report that it was sent" do
    configuration = RecordingStudioAccessible.configuration
    previous = configuration.access_invitation_notifier
    configuration.access_invitation_notifier = ->(**) { false }

    result = invite_email("notifier-false@example.com")

    assert result.failure?
    assert_equal "Invitation could not be sent.", result.error
    refute_equal "Invitation sent.", result.value&.notice
    assert_equal 1, RecordingStudioAccessible::AccessInvitation.where(email: "notifier-false@example.com").count
    assert_empty ActionMailer::Base.deliveries
  ensure
    configuration.access_invitation_notifier = previous
  end

  test "a raised notifier keeps the invitation and reports delivery failure" do
    configuration = RecordingStudioAccessible.configuration
    previous = configuration.access_invitation_notifier
    configuration.access_invitation_notifier = ->(**) { raise "smtp down" }

    result = invite_email("notifier-raise@example.com")

    assert result.failure?
    assert_equal "Invitation could not be sent.", result.error
    assert_equal 1, RecordingStudioAccessible::AccessInvitation.where(email: "notifier-raise@example.com").count
    assert_empty ActionMailer::Base.deliveries
  ensure
    configuration.access_invitation_notifier = previous
  end

  test "a notifier result with success false is delivery failure" do
    configuration = RecordingStudioAccessible.configuration
    previous = configuration.access_invitation_notifier
    configuration.access_invitation_notifier = lambda { |**|
      RecordingStudioAccessible::Services::BaseService::Result.new(success: false, error: "mailbox rejected")
    }

    result = invite_email("notifier-result@example.com")

    assert result.failure?
    assert_equal "Invitation could not be sent.", result.error
    assert_equal 1, RecordingStudioAccessible::AccessInvitation.where(email: "notifier-result@example.com").count
  ensure
    configuration.access_invitation_notifier = previous
  end

  test "a missing acceptance url keeps the invitation and reports delivery failure" do
    previous_options = ActionMailer::Base.default_url_options.dup
    ActionMailer::Base.default_url_options = {}

    result = invite_email("no-url@example.com")

    assert result.failure?
    assert_equal "Invitation could not be sent.", result.error
    assert_equal 1, RecordingStudioAccessible::AccessInvitation.where(email: "no-url@example.com").count
    assert_empty ActionMailer::Base.deliveries
  ensure
    ActionMailer::Base.default_url_options = previous_options
  end

  test "failed resend keeps the delivered token until a later resend succeeds" do
    configuration = RecordingStudioAccessible.configuration
    previous = configuration.access_invitation_notifier
    invited = invite_email("person@example.com")
    token_a = token_from_last_delivery
    invitation = RecordingStudioAccessible::AccessInvitation.locate(token_a)
    assert invited.success?
    assert_equal invitation, RecordingStudioAccessible::AccessInvitation.locate(token_a)
    snapshot = {
      token_digest: invitation.token_digest,
      expires_at: invitation.expires_at,
      last_sent_at: invitation.last_sent_at,
      role: invitation.role,
      manager_actor_id: invitation.manager_actor_id
    }
    replacement_manager = create_user("resend-manager@example.com")
    granted = RecordingStudioAccessible.grant_access(
      recording: @recording,
      actor: replacement_manager,
      role: :admin,
      manager_actor: @manager
    )
    assert granted.success?, granted.error

    configuration.access_invitation_notifier = ->(**) { false }
    failed = invite_email("person@example.com", role: :edit, manager: replacement_manager)

    assert failed.failure?
    assert_equal "Invitation could not be sent.", failed.error
    invitation.reload
    assert_equal invitation, RecordingStudioAccessible::AccessInvitation.locate(token_a)
    assert_equal snapshot[:token_digest], invitation.token_digest
    assert_equal snapshot[:expires_at], invitation.expires_at
    assert_equal snapshot[:last_sent_at], invitation.last_sent_at
    assert_equal snapshot[:role], invitation.role
    assert_equal snapshot[:manager_actor_id], invitation.manager_actor_id
    assert_equal "view", invitation.role

    configuration.access_invitation_notifier = previous
    ActionMailer::Base.deliveries.clear
    resent = invite_email("person@example.com", role: :edit, manager: replacement_manager)
    token_b = token_from_last_delivery

    assert resent.success?
    assert_equal "Invitation sent.", resent.value.notice
    refute_equal token_a, token_b
    assert_nil RecordingStudioAccessible::AccessInvitation.locate(token_a)
    assert_equal invitation, RecordingStudioAccessible::AccessInvitation.locate(token_b)
    invitation.reload
    assert_equal "edit", invitation.role
    assert_equal replacement_manager.id, invitation.manager_actor_id
    assert_operator invitation.expires_at, :>, snapshot[:expires_at]
    assert_operator invitation.last_sent_at, :>, snapshot[:last_sent_at]
    assert_equal 1, RecordingStudioAccessible::AccessInvitation.unclosed.where(email: "person@example.com").count
  ensure
    configuration.access_invitation_notifier = previous
  end

  test "resend delivers an invitation that previously failed to send" do
    configuration = RecordingStudioAccessible.configuration
    previous = configuration.access_invitation_notifier
    configuration.access_invitation_notifier = ->(**) { false }
    failed = invite_email("retry-delivery@example.com")
    invitation = RecordingStudioAccessible::AccessInvitation.find_by!(email: "retry-delivery@example.com")
    configuration.access_invitation_notifier = previous

    retried = invite_email("retry-delivery@example.com", role: :edit)

    assert failed.failure?
    assert_equal "Invitation could not be sent.", failed.error
    assert retried.success?
    assert_equal "Invitation sent.", retried.value.notice
    assert_equal invitation.id, retried.value.pending.id
    assert_equal "edit", invitation.reload.role
    assert_equal 1, RecordingStudioAccessible::AccessInvitation.where(email: "retry-delivery@example.com").count
    refute_nil ActionMailer::Base.deliveries.last
    assert_includes ActionMailer::Base.deliveries.last.body.encoded, "Accept the invitation"
  end

  test "unknown email creates an invitation and no access grant and no user" do
    assert_no_difference -> { User.count } do
      assert_no_difference -> { RecordingStudio::Access.count } do
        @result = invite_email("unknown@example.com")
      end
    end

    assert @result.success?
    assert @result.value.invited?
    assert_equal "Invitation sent.", @result.value.notice
    assert_equal "unknown@example.com", @result.value.pending.email
    assert_equal "view", @result.value.pending.role
    assert_equal false, @result.value.pending.expired
    assert_nil User.find_by(email: "unknown@example.com")
    invitation = unclosed_invitation("unknown@example.com")
    assert_equal invitation.id, @result.value.pending.id
    assert_nil invitation.accepted_at
    assert_in_delta 14.days.from_now, invitation.expires_at, 5
  end

  test "email normalization keeps one unclosed row" do
    first = invite_email(" Person@Example.com ")
    second = invite_email("person@example.com")

    assert first.success?
    assert second.success?
    assert_equal 1, RecordingStudioAccessible::AccessInvitation.unclosed.where(email: "person@example.com").count
    invitation = unclosed_invitation("person@example.com")
    assert_equal "person@example.com", invitation.email
    assert_equal first.value.pending.id, invitation.id
    assert_equal second.value.pending.id, invitation.id
  end

  test "reinvite updates the same unclosed row and rotates the digest" do
    invite_email("rotate@example.com")
    old_token = token_from_last_delivery
    invitation = unclosed_invitation("rotate@example.com")
    assert_equal invitation, RecordingStudioAccessible::AccessInvitation.locate(old_token)

    ActionMailer::Base.deliveries.clear
    again = invite_email("rotate@example.com", role: :edit)
    new_token = token_from_last_delivery

    assert again.success?
    assert_equal invitation.id, unclosed_invitation("rotate@example.com").id
    assert_equal "edit", unclosed_invitation("rotate@example.com").role
    assert_equal 1, RecordingStudioAccessible::AccessInvitation.unclosed.count
    assert_nil RecordingStudioAccessible::AccessInvitation.locate(old_token)
    assert_equal invitation, RecordingStudioAccessible::AccessInvitation.locate(new_token)
    refute_equal old_token, new_token
  end

  test "two recordings may invite the same email" do
    folder = Folder.create!(workspace: @workspace, name: "Invite Folder", summary: "Folder", position: 1)
    folder_recording = create_child_recording(recordable: folder, parent_recording: @recording)

    root_result = invite_email("shared@example.com")
    folder_result = invite_email("shared@example.com", recording: folder_recording)

    assert root_result.success?
    assert folder_result.success?
    rows = RecordingStudioAccessible::AccessInvitation.unclosed.where(email: "shared@example.com")
    assert_equal 2, rows.count
    assert_equal [@recording.id, folder_recording.id].sort, rows.map(&:recording_id).sort
  end

  test "pending invitation does not authorize the actor" do
    invite_email("pending@example.com")
    user = create_user("pending@example.com")

    refute RecordingStudioAccessible.authorized?(actor: user, recording: @recording, role: :view)
    assert_nil RecordingStudioAccessible.role_for(actor: user, recording: @recording)
  end

  test "accept creates access through grant" do
    invite_email("accept@example.com")
    invitation = unclosed_invitation("accept@example.com")
    user = create_user("accept@example.com")

    assert_difference -> { RecordingStudio::Access.count }, 1 do
      @result = RecordingStudioAccessible.accept_access_invitation(invitation: invitation, actor: user)
    end

    assert @result.success?
    assert @result.value.granted?
    assert_equal "Access granted.", @result.value.notice
    assert_equal user, @result.value.access_recording.recordable.actor
    assert_equal "view", @result.value.access_recording.recordable.role
    assert invitation.reload.accepted?
    assert_equal user, invitation.accepted_by_actor
    assert RecordingStudioAccessible.authorized?(actor: user, recording: @recording, role: :view)
    assert_equal :view, RecordingStudioAccessible.role_for(actor: user, recording: @recording)
  end

  test "mismatched email is rejected and no access row appears" do
    invite_email("invited@example.com")
    invitation = unclosed_invitation("invited@example.com")
    other = create_user("other@example.com")

    assert_no_difference -> { RecordingStudio::Access.count } do
      @result = RecordingStudioAccessible.accept_access_invitation(invitation: invitation, actor: other)
    end

    assert @result.failure?
    assert_equal "This invitation was sent to a different email", @result.error
    assert_nil invitation.reload.accepted_at
    refute RecordingStudioAccessible.authorized?(actor: other, recording: @recording, role: :view)
  end

  test "expired invitation stays unclosed so resend refreshes that row" do
    invite_email("slot@example.com")
    invitation = unclosed_invitation("slot@example.com")
    invitation.update!(expires_at: 1.minute.ago)

    assert invitation.expired?
    assert_equal invitation, RecordingStudioAccessible::AccessInvitation.unclosed.find_by!(email: "slot@example.com")

    again = invite_email("slot@example.com", role: :edit)

    assert again.success?
    assert_equal invitation.id, unclosed_invitation("slot@example.com").id
    assert_equal "edit", unclosed_invitation("slot@example.com").role
    assert_equal 1, RecordingStudioAccessible::AccessInvitation.unclosed.where(email: "slot@example.com").count
    refute unclosed_invitation("slot@example.com").expired?
  end

  test "expired invitation is rejected" do
    invite_email("expired@example.com")
    invitation = unclosed_invitation("expired@example.com")
    invitation.update!(expires_at: 1.minute.ago)
    user = create_user("expired@example.com")

    assert_no_difference -> { RecordingStudio::Access.count } do
      @result = RecordingStudioAccessible.accept_access_invitation(invitation: invitation, actor: user)
    end

    assert @result.failure?
    assert_equal "Invitation has expired", @result.error
    refute RecordingStudioAccessible.authorized?(actor: user, recording: @recording, role: :view)
    assert_nil RecordingStudioAccessible.role_for(actor: user, recording: @recording)
  end

  test "revoked invitation is rejected" do
    invite_email("revoked-accept@example.com")
    invitation = unclosed_invitation("revoked-accept@example.com")
    user = create_user("revoked-accept@example.com")
    revoke = RecordingStudioAccessible.revoke_access_invitation(invitation: invitation, manager_actor: @manager)
    assert revoke.success?

    assert_no_difference -> { RecordingStudio::Access.count } do
      @result = RecordingStudioAccessible.accept_access_invitation(invitation: invitation.reload, actor: user)
    end

    assert @result.failure?
    assert_equal "Invitation was revoked", @result.error
  end

  test "accepted invitation cannot grant again after the access grant is revoked" do
    invite_email("reuse@example.com")
    invitation = unclosed_invitation("reuse@example.com")
    user = create_user("reuse@example.com")
    accepted = RecordingStudioAccessible.accept_access_invitation(invitation: invitation, actor: user)
    assert accepted.success?
    access_recording = accepted.value.access_recording

    removed = RecordingStudioAccessible::Services::RevokeRecordingAccess.call(
      recording: @recording,
      access_recording: access_recording,
      manager_actor: @manager
    )
    assert removed.success?

    assert_no_difference -> { RecordingStudio::Access.count } do
      @result = RecordingStudioAccessible.accept_access_invitation(invitation: invitation.reload, actor: user)
    end

    assert @result.success?
    assert @result.value.granted?
    assert_equal "Invitation already accepted.", @result.value.notice
    assert_nil @result.value.access_recording
    refute RecordingStudioAccessible.authorized?(actor: user, recording: @recording, role: :view)
    assert_nil RecordingStudioAccessible.role_for(actor: user, recording: @recording)
  end

  test "manager without admin cannot invite" do
    viewer = create_user("viewer-invite@example.com")
    grant = RecordingStudioAccessible.grant_access(
      recording: @recording,
      actor: viewer,
      role: :view,
      manager_actor: @manager
    )
    assert grant.success?

    result = invite_email("blocked@example.com", manager: viewer)

    assert result.failure?
    assert_equal "Not authorized to manage access", result.error
    assert_nil RecordingStudioAccessible::AccessInvitation.find_by(email: "blocked@example.com")
  end

  test "accept fails when the inviting manager no longer has admin" do
    invite_email("late@example.com")
    invitation = unclosed_invitation("late@example.com")
    other_admin = create_user("other-admin@example.com")
    grant = RecordingStudioAccessible.grant_access(
      recording: @recording,
      actor: other_admin,
      role: :admin,
      manager_actor: @manager
    )
    assert grant.success?
    manager_access = RecordingStudioAccessible::DirectAccessQuery.access_recordings_for_actor(
      recording: @recording,
      actor: @manager
    ).first
    removed = RecordingStudioAccessible::Services::RevokeRecordingAccess.call(
      recording: @recording,
      access_recording: manager_access,
      manager_actor: other_admin
    )
    assert removed.success?
    user = create_user("late@example.com")

    assert_no_difference -> { RecordingStudio::Access.count } do
      @result = RecordingStudioAccessible.accept_access_invitation(invitation: invitation, actor: user)
    end

    assert @result.failure?
    assert_equal "Not authorized to manage access", @result.error
    assert_nil invitation.reload.accepted_at
    refute RecordingStudioAccessible.authorized?(actor: user, recording: @recording, role: :view)
    assert_nil RecordingStudioAccessible.role_for(actor: user, recording: @recording)
  end

  test "shared root recording cannot be invited" do
    message_root = MessageRoot.create!(name: "Shared Messages Root")
    message_root_recording = create_root_recording(message_root)
    create_legacy_shared_root_access(actor: @manager, role: :admin, recording: message_root_recording)

    result = invite_email("shared-root@example.com", recording: message_root_recording)

    assert result.failure?
    assert_equal RecordingStudioAccessible::SharedRootAccess::GRANT_DENIED_MESSAGE, result.error
    assert_nil RecordingStudioAccessible::AccessInvitation.find_by(email: "shared-root@example.com")
  end

  test "invalid role is rejected" do
    result = invite_email("role@example.com", role: "owner")

    assert result.failure?
    assert_equal "Role is invalid", result.error
    assert_nil RecordingStudioAccessible::AccessInvitation.find_by(email: "role@example.com")
  end

  test "blank and invalid emails are rejected" do
    blank = invite_email("  ")
    invalid = invite_email("not-an-email")
    missing_recording = RecordingStudioAccessible.invite_access(
      recording: nil,
      email: "person@example.com",
      role: :view,
      manager_actor: @manager
    )

    assert blank.failure?
    assert_equal "Email is required", blank.error
    assert invalid.failure?
    assert_equal "Email is invalid", invalid.error
    assert missing_recording.failure?
    assert_equal "Recording is required", missing_recording.error
  end

  test "revoke works and a second revoke succeeds" do
    invite_email("revoke@example.com")
    invitation = unclosed_invitation("revoke@example.com")

    first = RecordingStudioAccessible.revoke_access_invitation(invitation: invitation, manager_actor: @manager)
    revoked_at = invitation.reload.revoked_at
    second = RecordingStudioAccessible.revoke_access_invitation(invitation: invitation, manager_actor: @manager)

    assert first.success?
    assert first.value.revoked?
    assert_equal "Invitation revoked.", first.value.notice
    assert invitation.revoked?
    assert second.success?
    assert second.value.revoked?
    assert_equal "Invitation revoked.", second.value.notice
    assert_equal revoked_at, invitation.reload.revoked_at
  end

  test "resend refresh keeps one unclosed row" do
    first = invite_email("refresh@example.com", role: :view)
    second = invite_email("refresh@example.com", role: :edit)

    assert first.success?
    assert second.success?
    rows = RecordingStudioAccessible::AccessInvitation.where(email: "refresh@example.com")
    assert_equal 1, rows.count
    assert_equal "edit", rows.first.role
    assert_nil rows.first.accepted_at
    assert_nil rows.first.revoked_at
  end

  test "invite access does not call the missing actor handler" do
    called = false
    previous = RecordingStudioAccessible.configuration.access_management_missing_actor_handler
    RecordingStudioAccessible.configuration.access_management_missing_actor_handler = lambda do |**|
      called = true
      raise "missing actor handler should not run"
    end

    result = invite_email("handler@example.com")

    assert result.success?
    assert result.value.invited?
    refute called
    assert unclosed_invitation("handler@example.com")
  ensure
    RecordingStudioAccessible.configuration.access_management_missing_actor_handler = previous
  end

  test "missing invitation and unsigned actor are rejected" do
    user = create_user("signed-out@example.com")
    missing_accept = RecordingStudioAccessible.accept_access_invitation(invitation: nil, actor: user)
    missing_revoke = RecordingStudioAccessible.revoke_access_invitation(invitation: nil, manager_actor: @manager)
    invite_email("unsigned@example.com")
    unsigned = RecordingStudioAccessible.accept_access_invitation(
      invitation: unclosed_invitation("unsigned@example.com"),
      actor: nil
    )

    assert missing_accept.failure?
    assert_equal "Invitation was not found", missing_accept.error
    assert missing_revoke.failure?
    assert_equal "Invitation was not found", missing_revoke.error
    assert unsigned.failure?
    assert_equal "Sign in to accept this invitation", unsigned.error
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def invite_email(email, role: :view, recording: @recording, manager: @manager)
    RecordingStudioAccessible.invite_access(
      recording: recording,
      email: email,
      role: role,
      manager_actor: manager
    )
  end

  def unclosed_invitation(email, recording: @recording)
    RecordingStudioAccessible::AccessInvitation.unclosed.find_by!(
      recording_id: recording.id,
      email: email.to_s.strip.downcase
    )
  end

  def token_from_last_delivery
    ActionMailer::Base.deliveries.last.body.encoded[/access_invitations\/([A-Za-z0-9_-]+)/, 1]
  end

  def create_legacy_shared_root_access(actor:, role:, recording:)
    connection = ActiveRecord::Base.connection
    access_id = SecureRandom.uuid
    recording_id = SecureRandom.uuid
    now = Time.current.utc.iso8601(6)
    stored_role = role.to_s

    connection.exec_insert(<<~SQL.squish, "SQL", [])
      INSERT INTO recording_studio_accesses
        (id, actor_type, actor_id, role, created_at)
      VALUES
        (#{connection.quote(access_id)}, #{connection.quote(RecordingStudioAccessible::ActorType.for(actor))},
         #{connection.quote(actor.id)}, #{connection.quote(stored_role)}, #{connection.quote(now)})
    SQL
    connection.exec_insert(<<~SQL.squish, "SQL", [])
      INSERT INTO recording_studio_recordings
        (id, recordable_type, recordable_id, parent_recording_id, root_recording_id, created_at, updated_at)
      VALUES
        (#{connection.quote(recording_id)}, 'RecordingStudio::Access', #{connection.quote(access_id)},
         #{connection.quote(recording.id)}, #{connection.quote(recording.id)},
         #{connection.quote(now)}, #{connection.quote(now)})
    SQL
    RecordingStudio::Recording.unscoped.find(recording_id)
  end
end
