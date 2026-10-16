# frozen_string_literal: true

require_relative "../test_helper"

class AccessRequestTransitionTest < ActiveSupport::TestCase
  setup do
    ActionMailer::Base.deliveries.clear
    @manager = create_user("transition-manager@example.com")
    @person = create_user("transition-person@example.com")
    @workspace = Workspace.create!(name: "Transition Workspace")
    @recording = create_root_recording(@workspace)
    create_direct_access_recording(actor: @manager, role: :admin, parent_recording: @recording)
    @configuration = RecordingStudioAccessible.configuration
    @previous_denied_notifier = @configuration.access_request_denied_notifier
  end

  teardown do
    @configuration.access_request_denied_notifier = @previous_denied_notifier
  end

  test "pending to approved grants access, emails, and fires the approved hook" do
    request_recording = ask
    ActionMailer::Base.deliveries.clear

    result = nil
    with_hook(:access_request_approved) do |hooks|
      assert_difference -> { grants }, 1 do
        result = transition(request_recording, "approved", role: "edit")
      end
      assert_includes hooks, result.value
    end

    assert result.success?
    snapshot = result.value.recordable
    assert_equal "approved", snapshot.status
    assert_equal "edit", snapshot.role
    assert_equal grants_relation.first.id, snapshot.access_recording_id
    assert_nil snapshot.review_note
    assert_equal "approved", latest_event(result.value)
    assert_includes ActionMailer::Base.deliveries.map(&:to).flatten, @person.email
  end

  test "pending to denied records the note, fires the hook, and skips email unless configured" do
    request_recording = ask
    ActionMailer::Base.deliveries.clear
    delivered = []
    @configuration.access_request_denied_notifier = ->(request_recording:, **_) { delivered << request_recording }

    result = nil
    with_hook(:access_request_denied) do |hooks|
      assert_no_difference -> { grants } do
        result = transition(request_recording, "denied", review_note: "Not now")
      end
      assert_includes hooks, result.value
    end

    assert result.success?
    assert_equal "denied", result.value.recordable.status
    assert_equal "Not now", result.value.recordable.review_note
    assert_nil result.value.recordable.access_recording_id
    assert_equal "denied", latest_event(result.value)
    assert_equal [result.value], delivered
    assert_empty ActionMailer::Base.deliveries
  end

  test "approved to pending revokes the grant and clears review stamps" do
    request_recording = approve(ask)

    result = nil
    with_hook(:access_request_reopened) do |hooks|
      assert_difference -> { grants }, -1 do
        result = transition(request_recording, "pending")
      end
      assert_includes hooks, result.value
    end

    snapshot = result.value.recordable
    assert result.success?
    assert_equal "pending", snapshot.status
    assert_nil snapshot.role
    assert_nil snapshot.review_note
    assert_nil snapshot.access_recording_id
    assert_equal "Please", snapshot.message
    assert_equal "reopened", latest_event(result.value)
  end

  test "approved to denied revokes the grant and fires the denied hook" do
    request_recording = approve(ask)

    result = nil
    with_hook(:access_request_denied) do |hooks|
      assert_difference -> { grants }, -1 do
        result = transition(request_recording, "denied", review_note: "Changed our mind")
      end
      assert_includes hooks, result.value
    end

    snapshot = result.value.recordable
    assert_equal "denied", snapshot.status
    assert_nil snapshot.access_recording_id
    assert_equal "Changed our mind", snapshot.review_note
    assert_equal "denied", latest_event(result.value)
    assert_equal 0, grants
  end

  test "denied to pending clears the review note" do
    request_recording = deny(ask)

    result = transition(request_recording, "pending")

    assert result.success?
    assert_equal "pending", result.value.recordable.status
    assert_nil result.value.recordable.review_note
    assert_nil result.value.recordable.role
    assert_equal 0, grants
    assert_equal "reopened", latest_event(result.value)
  end

  test "denied to approved grants access again and clears the review note" do
    request_recording = deny(ask)
    ActionMailer::Base.deliveries.clear

    result = nil
    with_hook(:access_request_approved) do |hooks|
      assert_difference -> { grants }, 1 do
        result = transition(request_recording, "approved", role: "view")
      end
      assert_includes hooks, result.value
    end

    snapshot = result.value.recordable
    assert_equal "approved", snapshot.status
    assert_nil snapshot.review_note
    assert_equal "view", snapshot.role
    assert_equal grants_relation.first.id, snapshot.access_recording_id
    assert_includes ActionMailer::Base.deliveries.map(&:to).flatten, @person.email
  end

  test "a status cannot move to itself or to an unknown status" do
    request_recording = ask

    same = transition(request_recording, "pending")
    unknown = transition(request_recording, "withdrawn")

    refute same.success?
    refute unknown.success?
    assert_equal "pending", request_recording.reload.recordable.status
    assert_equal 0, grants
  end

  test "approval cannot grant a role above the manager" do
    previous = @configuration.access_management_authorizer
    editor = create_user("transition-editor@example.com")
    create_direct_access_recording(actor: editor, role: :edit, parent_recording: @recording)
    @configuration.access_management_authorizer = ->(**) { true }
    request_recording = ask

    result = RecordingStudioAccessible.approve_access_request(
      request_recording: request_recording, manager_actor: editor, role: "admin"
    )

    refute result.success?
    assert_equal "You can only grant a role you already hold.", result.error
    assert_equal "pending", request_recording.reload.recordable.status
    assert_equal 0, grants
  ensure
    @configuration.access_management_authorizer = previous
  end

  test "reopening checks for another pending request inside the lock" do
    denied = deny(ask)
    ask
    real = RecordingStudioAccessible::AccessRequestQuery.method(:pending_for)
    calls = 0
    RecordingStudioAccessible::AccessRequestQuery.define_singleton_method(:pending_for) do |**kwargs|
      calls += 1
      next RecordingStudio::Recording.none if calls == 1

      real.call(**kwargs)
    end

    result = transition(denied, "pending")

    refute result.success?
    assert_equal "Only one open request is allowed per person.", result.error
    assert_equal "denied", denied.reload.recordable.status
    assert_equal 1, RecordingStudioAccessible::AccessRequestQuery.pending_for(recording: @recording, actor: @person).count
  ensure
    RecordingStudioAccessible::AccessRequestQuery.define_singleton_method(:pending_for, real) if real
  end

  test "the database allows only one pending request per person and target" do
    request_recording = ask
    assert_equal @recording.id, request_recording.recordable.target_recording_id

    assert_raises(ActiveRecord::RecordNotUnique) do
      RecordingStudioAccessible::AccessRequestCreationContext.allow do
        RecordingStudio::AccessRequest.create!(
          actor: @person, status: "pending", target_recording_id: @recording.id,
          pending_key: request_recording.recordable.pending_key
        )
      end
    end
  end

  test "leaving approved revokes a trashed grant" do
    request_recording = approve(ask)
    access_recording = RecordingStudio::Recording.unscoped.find(request_recording.recordable.access_recording_id)
    access_recording.update!(trashed_at: Time.current)

    result = transition(request_recording, "denied", review_note: "No longer")

    assert result.success?
    assert_nil result.value.recordable.access_recording_id
    assert_nil RecordingStudio::Recording.unscoped.find_by(id: access_recording.id)
  end

  test "leaving approved still clears the stamp when the grant is already gone" do
    request_recording = approve(ask)
    access_recording = RecordingStudio::Recording.unscoped.find(request_recording.recordable.access_recording_id)
    RecordingStudioAccessible::Services::RevokeRecordingAccess.call(
      recording: @recording, access_recording: access_recording, manager_actor: @manager
    )

    result = transition(request_recording, "pending")

    assert result.success?
    assert_nil result.value.recordable.access_recording_id
    assert_equal "pending", result.value.recordable.status
    assert_equal "reopened", latest_event(result.value)
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def ask
    RecordingStudioAccessible.request_access(
      recording: @recording, actor: @person, role: "view", message: "Please"
    ).value
  end

  def approve(request_recording)
    RecordingStudioAccessible.approve_access_request(
      request_recording: request_recording, manager_actor: @manager, role: "view"
    ).value
  end

  def deny(request_recording)
    RecordingStudioAccessible.deny_access_request(
      request_recording: request_recording, manager_actor: @manager, review_note: "Not now"
    ).value
  end

  def transition(request_recording, status, role: nil, review_note: nil)
    RecordingStudioAccessible.transition_access_request(
      request_recording: request_recording, status: status, manager_actor: @manager,
      role: role, review_note: review_note
    )
  end

  def grants
    grants_relation.count
  end

  def grants_relation
    RecordingStudioAccessible.access_recordings_for_actor(recording: @recording, actor: @person)
  end

  def latest_event(recording)
    recording.events.reorder(occurred_at: :asc, id: :asc).last.action
  end

  def with_hook(event)
    bucket = []
    @configuration.hooks.on(event) { |value| bucket << value }
    yield bucket
  ensure
    @configuration.hooks.instance_variable_get(:@registry)[event].pop
  end
end
