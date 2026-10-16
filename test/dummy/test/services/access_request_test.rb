# frozen_string_literal: true

require_relative "../test_helper"

class AccessRequestTest < ActiveSupport::TestCase
  setup do
    ActionMailer::Base.deliveries.clear
    @manager = create_user("access-request-manager@example.com")
    @person = create_user("access-request-person@example.com")
    @workspace = Workspace.create!(name: "Access Request Workspace")
    @recording = create_root_recording(@workspace)
    create_direct_access_recording(actor: @manager, role: :admin, parent_recording: @recording)
  end

  test "direct access request rows are rejected" do
    request = RecordingStudio::AccessRequest.new(actor: @person, role: "view", status: "pending")

    refute request.save
    assert_includes request.errors.full_messages.join, "request_access"
  end

  test "request access records a pending child and tells managers" do
    with_hook(:access_request_submitted) do |submitted|
      result = RecordingStudioAccessible.request_access(
        recording: @recording, actor: @person, role: "view", action: "read", message: "Need the notes"
      )

      assert result.success?
      request_recording = result.value
      assert_equal "pending", request_recording.recordable.status
      assert_equal "Need the notes", request_recording.recordable.message
      assert_equal "Need the notes", submitted_event(request_recording).recordable.message
      assert_includes ActionMailer::Base.deliveries.last.body.encoded, "Need the notes"
      assert_equal @recording.id, request_recording.parent_recording_id
      assert_equal "access_request_submitted", latest_event_action(request_recording)
      assert_includes submitted, request_recording
      assert_equal 1, ActionMailer::Base.deliveries.size
      assert_equal [ @manager.email ], ActionMailer::Base.deliveries.last.to
    end
  end

  test "a second request revises the open one without requiring a role" do
    first = RecordingStudioAccessible.request_access(recording: @recording, actor: @person, message: "First")
    second = RecordingStudioAccessible.request_access(
      recording: @recording, actor: @person, role: "edit", message: "Second"
    )

    assert_equal first.value.id, second.value.id
    assert_equal "edit", second.value.recordable.role
    assert_equal "Second", second.value.recordable.message
    assert_equal "resubmitted", latest_event_action(second.value)
    assert_equal 1, RecordingStudioAccessible::AccessRequestQuery.pending_for(recording: @recording, actor: @person).count
  end

  test "approval grants access and keeps the request history" do
    request_recording = RecordingStudioAccessible.request_access(
      recording: @recording, actor: @person, role: "view", message: "Please"
    ).value

    result = nil
    with_hook(:access_request_approved) do |approved_hooks|
      assert_difference -> { RecordingStudio::Access.count }, 1 do
        result = RecordingStudioAccessible.approve_access_request(
          request_recording: request_recording, manager_actor: @manager, role: "view"
        )
      end
      assert_includes approved_hooks, result.value
    end

    assert result.success?
    assert_equal "approved", result.value.recordable.status
    assert_equal result.value.recordable.access_recording_id, RecordingStudioAccessible.access_recordings_for_actor(
      recording: @recording, actor: @person
    ).first.id
    assert_includes result.value.events.map(&:action), "approved"
    assert ActionMailer::Base.deliveries.map(&:to).flatten.include?(@person.email)

    access_recording = RecordingStudio::Recording.unscoped.find(result.value.recordable.access_recording_id)
    RecordingStudioAccessible::Services::RevokeRecordingAccess.call(
      recording: @recording, access_recording: access_recording, manager_actor: @manager
    )
    result.value.reload
    assert_equal "approved", result.value.recordable.status
    assert_includes result.value.events.map(&:action), "approved"
  end

  test "a failed grant does not approve the request" do
    request_recording = RecordingStudioAccessible.request_access(
      recording: @recording, actor: @person, role: "view"
    ).value
    configuration = RecordingStudioAccessible.configuration
    previous_actor_types = configuration.access_actor_types
    configuration.access_actor_types = ["MissingActor"]

    result = RecordingStudioAccessible.approve_access_request(
      request_recording: request_recording, manager_actor: @manager, role: "view"
    )
    refute result.success?

    request_recording.reload
    assert request_recording.recordable.pending?
    assert_nil request_recording.recordable.access_recording_id
  ensure
    configuration.access_actor_types = previous_actor_types
  end

  test "deny closes the request without granting access" do
    request_recording = RecordingStudioAccessible.request_access(recording: @recording, actor: @person, role: "view").value
    ActionMailer::Base.deliveries.clear

    denied = nil
    with_hook(:access_request_denied) do |denied_hooks|
      denied = RecordingStudioAccessible.deny_access_request(
        request_recording: request_recording, manager_actor: @manager, review_note: "Not now"
      )
      assert_includes denied_hooks, denied.value
    end
    assert denied.success?
    assert_equal "denied", denied.value.recordable.status
    assert_equal "Not now", denied.value.recordable.review_note
    assert_equal 0, RecordingStudioAccessible.access_recordings_for_actor(recording: @recording, actor: @person).count
    assert_empty ActionMailer::Base.deliveries
  end

  test "someone else cannot see another person's request" do
    request_recording = RecordingStudioAccessible.request_access(recording: @recording, actor: @person, role: "view").value
    stranger = create_user("access-request-stranger@example.com")

    refute RecordingStudioAccessible::AccessRequestQuery.visible?(request_recording: request_recording, actor: stranger)
    assert RecordingStudioAccessible::AccessRequestQuery.visible?(request_recording: request_recording, actor: @person)
    assert RecordingStudioAccessible::AccessRequestQuery.visible?(request_recording: request_recording, actor: @manager)
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def submitted_event(recording)
    recording.events.reorder(occurred_at: :asc, id: :asc).find { |event| event.action == "access_request_submitted" }
  end

  def latest_event_action(recording)
    recording.events.reorder(occurred_at: :asc, id: :asc).last.action
  end

  def with_hook(event)
    bucket = []
    RecordingStudioAccessible.configuration.hooks.on(event) { |value| bucket << value }
    yield bucket
  ensure
    registry = RecordingStudioAccessible.configuration.hooks.instance_variable_get(:@registry)
    registry[event].pop
  end
end
