# frozen_string_literal: true

require_relative "../test_helper"

class SharedWithTest < ActiveSupport::TestCase
  setup do
    @configuration = RecordingStudioAccessible.configuration
    @original_resolver = @configuration.shared_item_resolver
    @owner = create_user("shared-with-owner-#{SecureRandom.hex(4)}@example.com")
    Current.actor = @owner
    @person = create_user("shared-with-person-#{SecureRandom.hex(4)}@example.com")
    @workspace = Workspace.create!(name: "Shared With #{SecureRandom.hex(4)}")
    @root = create_root_recording(@workspace)
    create_direct_access_recording(actor: @owner, role: :admin, parent_recording: @root)
    @configuration.shared_item_resolver = lambda do |recording|
      name = recording.recordable.name
      next if name.end_with?("hidden")

      { title: name, url: "/kits/#{recording.id}" }
    end
  end

  teardown do
    @configuration.shared_item_resolver = @original_resolver
    Current.actor = nil
  end

  test "an item share is listed with its role, workspace, and resolver link" do
    folder = share_folder("Launch kit")

    page = RecordingStudioAccessible.shared_with(actor: @person)
    item = page.items.first

    assert_equal 1, page.items.size
    assert_equal folder.recording, item.recording
    assert_equal "view", item.role
    assert_equal "View", item.role_label
    assert_equal @root, item.root
    assert_equal @workspace.name, item.workspace
    assert_equal "Launch kit", item.title
    assert_equal "/kits/#{folder.recording.id}", item.url
    assert_includes RecordingStudioAccessible.root_recording_ids_for(actor: @person), @root.id
  end

  test "a workspace grant hides that workspace, including item shares inside it" do
    other = other_workspace
    share_folder("Kept kit", workspace: other.workspace, root: other.root)
    share_folder("Hidden by workspace")
    create_direct_access_recording(actor: @person, role: :view, parent_recording: @root)

    items = RecordingStudioAccessible.shared_with(actor: @person).items

    assert_equal ["Kept kit"], items.map(&:title)
    assert_equal other.workspace.name, items.first.workspace
  end

  test "a revoked grant and a trashed grant are left out" do
    revoked = share_folder("Revoked kit")
    trashed = share_folder("Trashed grant")
    result = RecordingStudioAccessible.revoke_access(
      recording: revoked.recording, access_recording: revoked.grant, manager_actor: @owner
    )
    assert result.success?, result.error.to_s
    trashed.grant.update_column(:trashed_at, Time.current)

    assert_empty RecordingStudioAccessible.shared_with(actor: @person).items
  end

  test "a trashed item and a trashed ancestor are left out" do
    trashed_item = share_folder("Trashed kit")
    other = other_workspace
    share_folder("Buried kit", workspace: other.workspace, root: other.root)
    trashed_item.recording.update_column(:trashed_at, Time.current)
    other.root.update_column(:trashed_at, Time.current)

    assert_empty RecordingStudioAccessible.shared_with(actor: @person).items
  end

  test "a dependent grant is listed only while it is effective" do
    folder = share_folder("Dependent kit", actor: @owner, role: :admin)
    granted = RecordingStudioAccessible.grant_access(
      recording: folder.recording, actor: @person, role: :view, manager_actor: @owner, depends_on: folder.grant
    )
    assert granted.success?, granted.error.to_s

    assert_equal ["Dependent kit"], RecordingStudioAccessible.shared_with(actor: @person).items.map(&:title)

    folder.grant.update_column(:trashed_at, Time.current)

    assert_empty RecordingStudioAccessible.shared_with(actor: @person).items
  end

  test "a resolver that returns nil hides that row and an unset resolver hides every row" do
    share_folder("Visible kit")
    share_folder("Notes hidden")

    assert_equal ["Visible kit"], RecordingStudioAccessible.shared_with(actor: @person).items.map(&:title)

    @configuration.shared_item_resolver = nil

    assert_empty RecordingStudioAccessible.shared_with(actor: @person).items
  end

  test "pages walk newest first and a bad cursor is rejected" do
    11.times { |index| share_folder("Kit #{format('%02d', index)}", created_at: index.minutes.ago) }

    first = RecordingStudioAccessible.shared_with(actor: @person)
    assert_equal 10, first.items.size
    assert first.has_more
    assert_equal "Kit 00", first.items.first.title
    assert_equal "Kit 09", first.items.last.title

    second = RecordingStudioAccessible.shared_with(actor: @person, cursor: first.next_cursor)
    assert_equal ["Kit 10"], second.items.map(&:title)
    refute second.has_more

    assert_raises(RecordingStudioAccessible::SharedWith::InvalidCursor) do
      RecordingStudioAccessible.shared_with(actor: @person, cursor: "yesterday|not-a-uuid")
    end
    assert_raises(RecordingStudioAccessible::SharedWith::InvalidCursor) do
      RecordingStudioAccessible.shared_with(
        actor: @person,
        cursor: "not-a-time|00000000-0000-0000-0000-000000000000"
      )
    end
  end

  test "listing more items does not add a query per item" do
    2.times { |index| share_folder("Small #{index}") }
    small = query_count { RecordingStudioAccessible.shared_with(actor: @person) }

    6.times { |index| share_folder("Large #{index}") }
    large = query_count { RecordingStudioAccessible.shared_with(actor: @person) }

    assert_equal 2, RecordingStudioAccessible.shared_with(actor: @person).items.count { |item| item.title.start_with?("Small") }
    assert_equal 8, RecordingStudioAccessible.shared_with(actor: @person).items.size
    assert_equal small, large
    assert_operator large, :<=, 20
  end

  private

  def share_folder(name, actor: @person, role: :view, workspace: @workspace, root: @root, created_at: nil)
    folder = Folder.create!(workspace: workspace, name: name, summary: name, position: 0)
    recording = create_child_recording(recordable: folder, parent_recording: root)
    grant = create_direct_access_recording(actor: actor, role: role, parent_recording: recording)
    grant.update_columns(created_at: created_at) if created_at
    Struct.new(:recording, :grant, :workspace, :root).new(recording, grant, workspace, root)
  end

  def other_workspace
    @other_workspace ||= Workspace.create!(name: "Other Shared #{SecureRandom.hex(4)}")
    @other_root ||= create_root_recording(@other_workspace)
    create_direct_access_recording(actor: @owner, role: :admin, parent_recording: @other_root) unless
      RecordingStudioAccessible.authorized?(actor: @owner, recording: @other_root, role: :admin)
    Struct.new(:workspace, :root).new(@other_workspace, @other_root)
  end

  def query_count
    ActiveRecord::Base.connection.clear_query_cache
    count = 0
    callback = lambda do |*args|
      payload = ActiveSupport::Notifications::Event.new(*args).payload
      next if payload[:cached] || payload[:name] == "SCHEMA" || payload[:sql].to_s.match?(/\ABEGIN|\ACOMMIT|\AROLLBACK|\ASAVEPOINT|\ARELEASE/i)

      count += 1
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      ActiveRecord::Base.uncached { yield }
    end
    count
  end

  def create_user(email)
    User.create!(email: email, password: "Password", password_confirmation: "Password")
  end
end
