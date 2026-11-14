# frozen_string_literal: true

require "test_helper"

# Deleted events stay authorized, ordered, and all-or-nothing after record_events!.
class DeletedAccessEventsTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    add_events_count_column
    @user_ids = []
    @admin = create_user("deleted-events-admin@example.com")
    @workspace = Workspace.create!(name: "Deleted events #{SecureRandom.hex(4)}")
    @root = create_root_recording(@workspace)
    bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(recording: @root, actor: @admin)
    assert bootstrap.success?, bootstrap.error.to_s
    @folder_a = child_folder("A")
    @folder_b = child_folder("B")
    @grant_a = grant(create_user("deleted-events-a@example.com"), @folder_a)
    @grant_b = grant(create_user("deleted-events-b@example.com"), @folder_b)
    @grant_a2 = grant(create_user("deleted-events-a2@example.com"), @folder_a)
  end

  teardown do
    remove_created_rows
    remove_events_count_column
  end

  test "records deleted events in input order with the root and the right counts" do
    before_a = @folder_a.recordable.reload.events_count
    before_b = @folder_b.recordable.reload.events_count
    seen = []

    with_authorizer(lambda { |**context|
      seen << context.fetch(:recording).id
      true
    }) do
      RecordingStudioAccessible::Services::DeletedAccessEvents.write!(
        [@grant_a, @grant_b, @grant_a2],
        actor: @admin
      )
    end

    events = deleted_events
    assert_equal [@folder_a.id, @folder_b.id, @folder_a.id], events.map(&:recording_id)
    assert_equal ["deleted"] * 3, events.map(&:action)
    assert events.all? { |event| event.root_recording_id == @root.id }
    assert events.each_cons(2).all? { |earlier, later| earlier.occurred_at < later.occurred_at }
    assert_equal [@grant_a.id, @grant_b.id, @grant_a2.id], events.map { |event| event.metadata["access_recording_id"] }
    assert_equal @admin.id, events.first.actor_id
    assert_equal [@folder_a.id, @folder_b.id, @folder_a.id], seen
    assert_equal before_a + 2, @folder_a.recordable.reload.events_count
    assert_equal before_b + 1, @folder_b.recordable.reload.events_count
    assert RecordingStudioAccessible.authorized?(actor: @grant_a.recordable.actor, recording: @folder_a, role: :view)
  end

  test "refuses an unauthorized row and writes nothing" do
    before_events = RecordingStudio::Event.count
    before_a = @folder_a.recordable.reload.events_count
    before_b = @folder_b.recordable.reload.events_count
    seen = []

    error = with_authorizer(lambda { |**context|
      seen << context.fetch(:recording).id
      context.fetch(:recording).id != @folder_b.id
    }) do
      assert_raises(RecordingStudio::AuthorizationError) do
        RecordingStudioAccessible::Services::DeletedAccessEvents.write!(
          [@grant_a, @grant_b],
          actor: @admin
        )
      end
    end

    assert_equal [@folder_a.id, @folder_b.id], seen
    assert_match(/denied by config.authorize_write/, error.message)
    assert_equal before_events, RecordingStudio::Event.count
    assert_equal before_a, @folder_a.recordable.reload.events_count
    assert_equal before_b, @folder_b.recordable.reload.events_count
    assert RecordingStudioAccessible.authorized?(actor: @grant_b.recordable.actor, recording: @folder_b, role: :view)
  end

  test "rolls the batch and the counts back when the caller rolls back" do
    before_events = RecordingStudio::Event.count
    before_a = @folder_a.recordable.reload.events_count

    RecordingStudio::Recording.transaction do
      RecordingStudioAccessible::Services::DeletedAccessEvents.write!([@grant_a, @grant_a2], actor: @admin)
      raise ActiveRecord::Rollback
    end

    assert_equal before_events, RecordingStudio::Event.count
    assert_equal before_a, @folder_a.recordable.reload.events_count
    assert_empty deleted_events
  end

  private

  def with_authorizer(authorizer)
    previous = RecordingStudio.configuration.authorize_write
    RecordingStudio.configuration.authorize_write = authorizer
    yield
  ensure
    RecordingStudio.configuration.authorize_write = previous
  end

  def deleted_events
    RecordingStudio::Event.where(action: "deleted", recording_id: [@folder_a.id, @folder_b.id])
                          .order(:occurred_at, :created_at, :id)
                          .to_a
  end

  def add_events_count_column
    return if Folder.connection.column_exists?(:folders, :events_count)

    Folder.connection.add_column(:folders, :events_count, :integer, default: 0, null: false)
    Folder.reset_column_information
  end

  def remove_events_count_column
    return unless Folder.connection.column_exists?(:folders, :events_count)

    Folder.connection.remove_column(:folders, :events_count)
    Folder.reset_column_information
  end

  def remove_created_rows
    return if @root.nil?

    ids = RecordingStudio::Recording.unscoped.where(root_recording_id: @root.id).pluck(:id)
    ids << @root.id
    RecordingStudio::Event.where(recording_id: ids).delete_all
    access_ids = RecordingStudio::Recording.unscoped.where(id: ids, recordable_type: "RecordingStudio::Access")
                                           .pluck(:recordable_id)
    RecordingStudio::Recording.unscoped.where(id: ids).delete_all
    RecordingStudio::Access.where(id: access_ids).delete_all if access_ids.any?
    Folder.where(workspace_id: @workspace.id).delete_all if @workspace
    @workspace&.delete
    User.where(id: @user_ids).delete_all if @user_ids.present?
  end

  def child_folder(name)
    folder = Folder.create!(workspace: @workspace, name: name, summary: name, position: 0)
    create_child_recording(recordable: folder, parent_recording: @root)
  end

  def grant(actor, recording)
    result = RecordingStudioAccessible.grant_access(
      recording: recording, actor: actor, role: :view, manager_actor: @admin
    )
    assert result.success?, result.error.to_s
    result.value
  end

  def create_user(email)
    user = User.find_by(email: email) || User.create!(
      email: email, password: "Password", password_confirmation: "Password"
    )
    @user_ids << user.id
    user
  end
end
