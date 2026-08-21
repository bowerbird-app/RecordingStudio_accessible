require_relative "../test_helper"

class SharedForestSeedWiringTest < ActiveSupport::TestCase
  test "seeds bootstrap the message group owner then grant later members" do
    seeds = File.read(Rails.root.join("db/seeds.rb"))

    assert_includes seeds, "bootstrap_owner_access!"
    assert_includes seeds, "sync_shared_forest_access!"
    assert_includes seeds, "ensure_bootstrap_owner!"
    refute_includes seeds, "AccessCreationContext.allow"
    refute_includes seeds, "ensure_shared_forest_seed_access!"
  end

  test "shared forest first owner uses bootstrap then grant_access for later members" do
    original_access_actor_types = RecordingStudioAccessible.configuration.access_actor_types
    RecordingStudioAccessible.configuration.access_actor_types = [ "User", "Workspace" ]

    owner = User.find_by(email: "seed-group-owner@example.com") ||
            User.create!(email: "seed-group-owner@example.com", password: "Password", password_confirmation: "Password")
    workspace = Workspace.create!(name: "Seed Through Workspace")
    create_root_recording(workspace)

    message_root = MessageRoot.create!(name: "Seed Messages Root")
    message_root_recording = create_root_recording(message_root)
    message_group = MessageGroup.create!(
      message_root: message_root,
      name: "Seeded launch thread",
      summary: "Group seeded like the dummy demo",
      position: 0
    )
    message_group_recording = create_child_recording(
      recordable: message_group,
      parent_recording: message_root_recording
    )

    bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(
      recording: message_group_recording,
      actor: owner
    )
    assert bootstrap.success?
    assert_equal "admin", bootstrap.value.recordable.role

    later = RecordingStudioAccessible.grant_access(
      recording: message_group_recording,
      actor: workspace,
      role: :view,
      manager_actor: owner
    )
    assert later.success?
    assert_equal "view", later.value.recordable.role
    assert RecordingStudioAccessible.authorized?(actor: workspace, recording: message_group_recording, role: :view)
  ensure
    RecordingStudioAccessible.configuration.access_actor_types = original_access_actor_types
  end
end
