require_relative "../test_helper"

class BootstrapOwnerAccessTest < ActiveSupport::TestCase
  setup do
    @original_access_actor_types = RecordingStudioAccessible.configuration.access_actor_types
    @original_authorizer = RecordingStudioAccessible.configuration.access_management_authorizer
    RecordingStudioAccessible.configuration.access_actor_types = [ "User" ]
    # Keep the default authorizer so empty-root grant_access still fails closed.
    RecordingStudioAccessible.configuration.access_management_authorizer =
      RecordingStudioAccessible.configuration.method(:default_access_management_authorizer)

    @owner = create_user("bootstrap-owner@example.com")
    @invitee = create_user("bootstrap-invitee@example.com")
    @workspace = Workspace.create!(name: "Bootstrap Owner Workspace")
    @recording = create_root_recording(@workspace)
    @message_root = MessageRoot.create!(name: "Bootstrap Messages Root")
    @message_root_recording = create_root_recording(@message_root)
    @message_group = MessageGroup.create!(
      message_root: @message_root,
      name: "Bootstrap group",
      summary: "Accessible child under a shared root",
      position: 0
    )
    @message_group_recording = create_child_recording(
      recordable: @message_group,
      parent_recording: @message_root_recording
    )
  end

  teardown do
    RecordingStudioAccessible.configuration.access_actor_types = @original_access_actor_types
    RecordingStudioAccessible.configuration.access_management_authorizer = @original_authorizer
    Current.actor = nil if defined?(Current) && Current.respond_to?(:actor=)
  end

  test "bootstrap creates admin access on an empty owned root" do
    assert_difference -> { RecordingStudio::Access.count }, 1 do
      assert_difference -> { RecordingStudio::Recording.unscoped.count }, 1 do
        @result = RecordingStudioAccessible.bootstrap_owner_access!(
          recording: @recording,
          actor: @owner
        )
      end
    end

    assert @result.success?
    assert_kind_of RecordingStudio::Recording, @result.value
    assert_equal @owner, @result.value.recordable.actor
    assert_equal "admin", @result.value.recordable.role
    assert_equal @recording.id, @result.value.parent_recording_id
    assert RecordingStudioAccessible.authorized?(actor: @owner, recording: @recording, role: :admin)
  end

  test "bootstrap creates admin access on an empty accessible child under a shared root" do
    assert_difference -> { RecordingStudio::Access.count }, 1 do
      @result = RecordingStudioAccessible.bootstrap_owner_access!(
        recording: @message_group_recording,
        actor: @owner
      )
    end

    assert @result.success?
    assert_equal @owner, @result.value.recordable.actor
    assert_equal "admin", @result.value.recordable.role
    assert_equal @message_group_recording.id, @result.value.parent_recording_id
    assert RecordingStudioAccessible.authorized?(actor: @owner, recording: @message_group_recording, role: :admin)
  end

  test "bootstrap is idempotent when the only holder is already this actor as admin" do
    first = RecordingStudioAccessible.bootstrap_owner_access!(recording: @recording, actor: @owner)
    assert first.success?

    assert_no_difference -> { RecordingStudio::Access.count } do
      second = RecordingStudioAccessible.bootstrap_owner_access!(recording: @recording, actor: @owner)
      assert second.success?
      assert_equal first.value.id, second.value.id
    end
  end

  test "bootstrap is idempotent for the same actor admin on a shared-forest child" do
    first = RecordingStudioAccessible.bootstrap_owner_access!(
      recording: @message_group_recording,
      actor: @owner
    )
    assert first.success?

    assert_no_difference -> { RecordingStudio::Access.count } do
      second = RecordingStudioAccessible.bootstrap_owner_access!(
        recording: @message_group_recording,
        actor: @owner
      )
      assert second.success?
      assert_equal first.value.id, second.value.id
    end
  end

  test "second bootstrap fails when another holder already exists" do
    first = RecordingStudioAccessible.bootstrap_owner_access!(recording: @recording, actor: @owner)
    assert first.success?

    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: @recording, actor: @invitee)

    assert result.failure?
    assert_equal RecordingStudioAccessible::Services::BootstrapOwnerAccess::ALREADY_BOOTSTRAPPED_MESSAGE,
                 result.error
  end

  test "second bootstrap fails on a shared-forest child when another holder already exists" do
    first = RecordingStudioAccessible.bootstrap_owner_access!(
      recording: @message_group_recording,
      actor: @owner
    )
    assert first.success?

    result = RecordingStudioAccessible.bootstrap_owner_access!(
      recording: @message_group_recording,
      actor: @invitee
    )

    assert result.failure?
    assert_equal RecordingStudioAccessible::Services::BootstrapOwnerAccess::ALREADY_BOOTSTRAPPED_MESSAGE,
                 result.error
  end

  test "bootstrap rejects disallowed actor types" do
    RecordingStudioAccessible.configuration.access_actor_types = [ "Workspace" ]

    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: @recording, actor: @owner)

    assert result.failure?
    assert_equal "Actor type is not allowed for access", result.error
  end

  test "bootstrap rejects unpersisted recordings and actors" do
    unpersisted_recording = RecordingStudio::Recording.new
    unpersisted_user = User.new(email: "unpersisted@example.com")

    result = RecordingStudioAccessible.bootstrap_owner_access!(
      recording: unpersisted_recording,
      actor: @owner
    )
    assert result.failure?
    assert_equal RecordingStudioAccessible::Services::BootstrapOwnerAccess::RECORDING_NOT_PERSISTED_MESSAGE,
                 result.error

    result = RecordingStudioAccessible.bootstrap_owner_access!(
      recording: @recording,
      actor: unpersisted_user
    )
    assert result.failure?
    assert_equal RecordingStudioAccessible::Services::BootstrapOwnerAccess::ACTOR_NOT_PERSISTED_MESSAGE,
                 result.error
  end

  test "bootstrap rejects owned-root children that are not shared-forest accessible children" do
    folder = Folder.create!(workspace: @workspace, name: "Child", summary: "Folder", position: 0)
    folder_recording = create_child_recording(recordable: folder, parent_recording: @recording)
    page = Page.create!(folder: folder, title: "Child page", summary: "Page", position: 0)
    page_recording = create_child_recording(recordable: page, parent_recording: folder_recording)

    [ folder_recording, page_recording ].each do |child_recording|
      result = RecordingStudioAccessible.bootstrap_owner_access!(
        recording: child_recording,
        actor: @owner
      )

      assert result.failure?
      assert_equal RecordingStudioAccessible::Services::BootstrapOwnerAccess::UNSUPPORTED_RECORDING_MESSAGE,
                   result.error
    end
  end

  test "bootstrap rejects shared roots" do
    result = RecordingStudioAccessible.bootstrap_owner_access!(
      recording: @message_root_recording,
      actor: @owner
    )

    assert result.failure?
    assert_equal RecordingStudioAccessible::SharedRootAccess::GRANT_DENIED_MESSAGE, result.error
  end

  test "after bootstrap grant_access works for a second user with manager_actor" do
    bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(recording: @recording, actor: @owner)
    assert bootstrap.success?

    result = RecordingStudioAccessible.grant_access(
      recording: @recording,
      actor: @invitee,
      role: :view,
      manager_actor: @owner
    )

    assert result.success?
    assert_equal @invitee, result.value.recordable.actor
    assert_equal "view", result.value.recordable.role
    assert RecordingStudioAccessible.authorized?(actor: @invitee, recording: @recording, role: :view)
  end

  test "after bootstrap on a shared-forest child grant_access works for later members" do
    bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(
      recording: @message_group_recording,
      actor: @owner
    )
    assert bootstrap.success?

    workspace_actor = Workspace.create!(name: "Through Workspace")
    RecordingStudioAccessible.configuration.access_actor_types = [ "User", "Workspace" ]

    result = RecordingStudioAccessible.grant_access(
      recording: @message_group_recording,
      actor: workspace_actor,
      role: :view,
      manager_actor: @owner
    )

    assert result.success?
    assert_equal workspace_actor, result.value.recordable.actor
    assert_equal "view", result.value.recordable.role
  end

  test "grant_access without admin still fails on empty root" do
    empty_workspace = Workspace.create!(name: "Empty Authorizer Workspace")
    empty_root = create_root_recording(empty_workspace)

    result = RecordingStudioAccessible.grant_access(
      recording: empty_root,
      actor: @invitee,
      role: :admin,
      manager_actor: @owner
    )

    assert result.failure?
    assert_equal "Not authorized to manage access", result.error
  end

  test "grant_access without admin still fails on empty shared-forest child" do
    result = RecordingStudioAccessible.grant_access(
      recording: @message_group_recording,
      actor: @invitee,
      role: :admin,
      manager_actor: @owner
    )

    assert result.failure?
    assert_equal "Not authorized to manage access", result.error
  end

  test "concurrent bootstraps leave at most one admin grant path winner" do
    empty_workspace = Workspace.create!(name: "Race Bootstrap Workspace")
    empty_root = create_root_recording(empty_workspace)
    other_owner = create_user("bootstrap-racer@example.com")
    empty_root_id = empty_root.id
    owner_id = @owner.id
    other_owner_id = other_owner.id

    results = Queue.new
    errors = Queue.new
    barrier = Queue.new

    threads = [
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          barrier.pop
          results << RecordingStudioAccessible.bootstrap_owner_access!(
            recording: RecordingStudio::Recording.unscoped.find(empty_root_id),
            actor: User.find(owner_id)
          )
        end
      rescue StandardError => e
        errors << e
      end,
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          barrier.pop
          results << RecordingStudioAccessible.bootstrap_owner_access!(
            recording: RecordingStudio::Recording.unscoped.find(empty_root_id),
            actor: User.find(other_owner_id)
          )
        end
      rescue StandardError => e
        errors << e
      end
    ]

    2.times { barrier << true }
    threads.each(&:join)

    assert_empty Array.new(errors.size) { errors.pop }
    collected = Array.new(results.size) { results.pop }
    assert_equal 2, collected.size
    assert_equal 1, collected.count(&:success?)
    assert_equal 1, collected.count(&:failure?)
    assert_equal 1, RecordingStudioAccessible.access_recordings_for(empty_root).count
    assert_equal "admin", RecordingStudioAccessible.access_recordings_for(empty_root).first.recordable.role
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end
end
