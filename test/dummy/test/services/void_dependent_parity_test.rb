# frozen_string_literal: true

require_relative "../test_helper"

# The batched void must remove the same grants, write the same deleted events,
# and accept or roll back the last admin the same way as one destroy per grant.
class VoidDependentParityTest < ActiveSupport::TestCase
  setup do
    @admin = create_user("void-parity-admin@example.com")
    @editor = create_user("void-parity-editor@example.com")
    @viewer = create_user("void-parity-viewer@example.com")
    @other = create_user("void-parity-other@example.com")
    @workspace = Workspace.create!(name: "Void Parity")
    @root = create_root_recording(@workspace)
    bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(recording: @root, actor: @admin)
    assert bootstrap.success?, bootstrap.error.to_s
    @owner_grant = bootstrap.value
  end

  test "voiding matches per-grant destroy for rows, events, and notifications" do
    folder = child_folder("Kept")
    sibling = child_folder("Sibling")
    manager = grant(@editor, :edit, folder)
    kept = dependent_grant(@viewer, :view, folder, manager)
    doomed_actor = create_user("void-parity-doomed@example.com")
    weak = grant(@other, :view, sibling)
    doomed = dependent_grant(doomed_actor, :view, sibling, weak)
    trashed = dependent_grant(create_user("void-parity-trashed@example.com"), :view, sibling, weak)
    trashed.update_column(:trashed_at, Time.current)
    weak.update_column(:trashed_at, Time.current)

    reference = reference_outcome(weak.id, moved: false)
    outcome = service_outcome(weak.id, moved: false)

    assert_equal [doomed.id], reference.fetch(:voided_ids)
    refute_includes reference.fetch(:voided_ids), kept.id
    refute_includes reference.fetch(:voided_ids), trashed.id
    assert_equal reference, outcome
    assert_nil RecordingStudio::Recording.unscoped.find_by(id: doomed.id)
    assert RecordingStudio::Recording.exists?(kept.id)
    assert RecordingStudio::Recording.unscoped.exists?(trashed.id)
    assert RecordingStudioAccessible.authorized?(actor: @viewer, recording: folder, role: :view)
    refute RecordingStudioAccessible.authorized?(actor: doomed_actor, recording: sibling, role: :view)
  end

  test "moving the manager voids effective dependents and keeps the same events" do
    folder = child_folder("Moved")
    manager = grant(@editor, :edit, folder)
    dependent = dependent_grant(@viewer, :view, folder, manager)

    reference = reference_outcome(manager.id, moved: true)
    outcome = service_outcome(manager.id, moved: true)

    assert_equal [dependent.id], reference.fetch(:voided_ids)
    assert_equal reference, outcome
    assert_nil RecordingStudio::Recording.unscoped.find_by(id: dependent.id)
    assert RecordingStudio::Recording.exists?(manager.id)
    refute RecordingStudioAccessible.authorized?(actor: @viewer, recording: folder, role: :view)
    assert RecordingStudioAccessible.authorized?(actor: @editor, recording: folder, role: :edit)
  end

  test "a void that removes the last admin rolls back the whole batch" do
    folder = child_folder("Branch")
    grant_recording = child_folder("Other branch")
    manager = grant(@editor, :admin, folder)
    last_admin = dependent_grant(@other, :admin, @root, manager)
    revoke = RecordingStudioAccessible.revoke_access(
      recording: @root,
      access_recording: @owner_grant,
      manager_actor: @admin
    )
    assert revoke.success?, revoke.error.to_s

    reference = reference_outcome(manager.id, moved: true)
    outcome = service_outcome(manager.id, moved: true)

    assert_equal :failure, reference.fetch(:status)
    assert_equal "Add another admin before removing the last one.", reference.fetch(:error)
    assert_equal reference, outcome
    assert RecordingStudio::Recording.exists?(last_admin.id)
    assert RecordingStudio::Recording.exists?(manager.id)
    assert RecordingStudioAccessible.authorized?(actor: @other, recording: @root, role: :admin)
    assert grant_recording.present?
  end

  private

  def service_outcome(manager_id, moved:)
    before_event_ids = event_ids
    notifications = []
    subscriber = subscribe_events(notifications)
    result = RecordingStudioAccessible::Services::VoidDependentAccesses.call(
      manager_access_recording_id: manager_id,
      manager_actor: @admin,
      moved: moved
    )
    outcome_from(result, before_event_ids, notifications)
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  def reference_outcome(manager_id, moved:)
    selected = selected_recordings(manager_id, moved: moved)
    before_event_ids = event_ids
    notifications = []
    subscriber = subscribe_events(notifications)
    snapshot = nil
    begin
      RecordingStudio::Recording.transaction(requires_new: true) do
        voided = []
        RecordingStudioAccessible::LastAdminGuard.protect!(recordings: selected.map(&:parent_recording)) do
          selected.each do |recording|
            recorder.send(:destroy_access_recording!, recording, manager_actor: @admin)
            voided << recording.id
          end
        end
        snapshot = outcome_body(:success, voided, nil, before_event_ids, notifications)
        raise ActiveRecord::Rollback
      end
    rescue RecordingStudioAccessible::LastAdminError => e
      snapshot = outcome_body(:failure, [], e.message, before_event_ids, notifications)
    rescue StandardError
      snapshot = outcome_body(:failure, [], "Something went wrong. Try again.", before_event_ids, notifications)
    end
    snapshot
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  def outcome_from(result, before_event_ids, notifications)
    if result.success?
      outcome_body(:success, result.value, nil, before_event_ids, notifications)
    else
      outcome_body(:failure, [], result.error, before_event_ids, notifications)
    end
  end

  def outcome_body(status, voided_ids, error, before_event_ids, notifications)
    {
      status: status,
      voided_ids: Array(voided_ids).sort,
      error: error,
      events: event_signatures(event_ids - before_event_ids),
      grants: access_ids,
      notifications: notifications.map { |payload| payload.except(:event_id, :occurred_at) }
    }
  end

  def subscribe_events(notifications)
    ActiveSupport::Notifications.subscribe("recordings.event_created") do |*args|
      notifications << args.last.slice(
        :event_id, :action, :recording_id, :root_recording_id, :recordable_type, :recordable_id,
        :previous_recordable_type, :previous_recordable_id, :actor_type, :actor_id,
        :impersonator_type, :impersonator_id, :occurred_at, :metadata
      )
    end
  end

  def selected_recordings(manager_id, moved:)
    selected = []
    RecordingStudioAccessible::DirectAccessQuery.access_recordings_depending_on(manager_id).find_each do |recording|
      selected << recording if moved || !RecordingStudioAccessible::DependentAccess.effective?(recording)
    end
    selected
  end

  def event_ids
    RecordingStudio::Event.order(:occurred_at, :created_at, :id).pluck(:id)
  end

  def event_signatures(ids)
    return [] if ids.empty?

    RecordingStudio::Event.where(id: ids).order(:occurred_at, :created_at, :id).map do |event|
      {
        action: event.action,
        recording_id: event.recording_id,
        actor_type: event.actor_type,
        actor_id: event.actor_id,
        impersonator_type: event.impersonator_type,
        impersonator_id: event.impersonator_id,
        recordable_type: event.recordable_type,
        recordable_id: event.recordable_id,
        previous_recordable_type: event.previous_recordable_type,
        previous_recordable_id: event.previous_recordable_id,
        idempotency_key: event.idempotency_key,
        metadata: event.metadata
      }
    end
  end

  def access_ids
    RecordingStudio::Recording.unscoped.where(recordable_type: "RecordingStudio::Access").order(:id).pluck(:id)
  end

  def recorder
    @recorder ||= RecordingStudioAccessible::Services::VoidDependentAccesses.new(
      manager_access_recording_id: "reference"
    )
  end

  def child_folder(name)
    folder = Folder.create!(workspace: @workspace, name: name, summary: name, position: 0)
    create_child_recording(recordable: folder, parent_recording: @root)
  end

  def grant(actor, role, recording)
    result = RecordingStudioAccessible.grant_access(
      recording: recording, actor: actor, role: role, manager_actor: @admin
    )
    assert result.success?, result.error.to_s
    result.value
  end

  def dependent_grant(actor, role, recording, manager)
    result = RecordingStudioAccessible.grant_access(
      recording: recording,
      actor: actor,
      role: role,
      manager_actor: @admin,
      depends_on: manager
    )
    assert result.success?, result.error.to_s
    result.value
  end

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end
end
