require_relative "../test_helper"

class RecordingsForParityTest < ActiveSupport::TestCase
  KIT = :"presskits.kit_download"

  setup do
    @user = create_user("parity-user@example.com")
    @admin = create_user("parity-admin@example.com")
    @workspace = Workspace.create!(name: "Parity Workspace")
    @root = create_root_recording(@workspace)
    bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(recording: @root, actor: @admin)
    assert bootstrap.success?, bootstrap.error.to_s

    @original_action_audiences = RecordingStudioAccessible.configuration.action_audiences.to_h
  end

  teardown do
    RecordingStudioAccessible.configuration.action_audiences.replace(@original_action_audiences)
    if Folder.instance_variable_defined?(:@accessible_role_set)
      Folder.remove_instance_variable(:@accessible_role_set)
    end
  end

  test "allow and deny match the per-child resolver" do
    kept = add_folder("Kept")
    direct = add_folder("Direct")
    grant(@user, :view, @root)
    grant(@user, :edit, direct)

    assert_equal oracle_ids(@root), listed_ids(@root)
    assert_includes listed_ids(@root), kept.id
    refute_includes listed_ids(@root, minimum_role: :edit), kept.id
    assert_includes listed_ids(@root, minimum_role: :edit), direct.id

    other = add_folder("No grant")
    revoke_root_grant
    grant(@user, :view, kept)

    assert_equal [direct.id, kept.id].sort, listed_ids(@root)
    refute_includes listed_ids(@root), other.id
    assert_equal oracle_ids(@root), listed_ids(@root)
    assert_equal oracle_ids(@root, minimum_role: :edit), listed_ids(@root, minimum_role: :edit)
  end

  test "a parent admin and a child view still match edit" do
    child = add_folder("View child")
    grant(@user, :admin, @root)
    grant(@user, :view, child)

    assert_equal oracle_ids(@root, minimum_role: :edit), listed_ids(@root, minimum_role: :edit)
    assert_includes listed_ids(@root, minimum_role: :edit), child.id
  end

  test "audience and a narrowing constraint do not change membership" do
    configure_kit
    granted = add_folder("Granted")
    public_only = add_folder("Public only")
    grant(@user, :view, granted)
    RecordingStudioAccessible.set_audience!(recording: granted, action: KIT, audience: :public, actor: @admin)
    RecordingStudioAccessible.set_audience!(recording: public_only, action: KIT, audience: :public, actor: @admin)
    RecordingStudioAccessible.set_audience_constraint!(
      root: @root, action: KIT, allowed_audiences: %i[granted], actor: @admin
    )

    assert_equal :granted, RecordingStudioAccessible.effective_audience(recording: granted, action: KIT)
    snapshot = RecordingStudioAccessible::AudienceSnapshot.load([granted, public_only])
    assert_equal(
      RecordingStudioAccessible.effective_audience(recording: granted, action: KIT),
      RecordingStudioAccessible::AudienceResolver.effective_audience(
        recording: granted, action: KIT, snapshot: snapshot
      )
    )
    assert_equal(
      RecordingStudioAccessible.effective_audience(recording: public_only, action: KIT),
      RecordingStudioAccessible::AudienceResolver.effective_audience(
        recording: public_only, action: KIT, snapshot: snapshot
      )
    )
    loaded = RecordingStudioAccessible::AudienceQuery.rows_for([granted, public_only])
    assert_equal 2, loaded.count { |row| row.recordable_type == "RecordingStudio::AccessRule" }
    assert_equal oracle_ids(@root), listed_ids(@root)
    assert_includes listed_ids(@root), granted.id
    refute_includes listed_ids(@root), public_only.id
    assert_equal 1, rule_queries { listed_ids(@root) }
  end

  test "a voided dependent grant matches the resolver" do
    folder = add_folder("Dependent")
    page = add_page(folder)
    manager_grant = RecordingStudioAccessible.grant_access(
      recording: folder, actor: create_user("parity-holder@example.com"), role: :edit, manager_actor: @admin
    )
    assert manager_grant.success?, manager_grant.error.to_s
    dependent = RecordingStudioAccessible.grant_access(
      recording: folder, actor: @user, role: :view, manager_actor: @admin, depends_on: manager_grant.value
    )
    assert dependent.success?, dependent.error.to_s

    assert_equal oracle_ids(folder), listed_ids(folder)
    assert_includes listed_ids(folder), page.id

    manager_grant.value.update_column(:trashed_at, Time.current)

    assert_equal oracle_ids(folder), listed_ids(folder)
    refute_includes listed_ids(folder), page.id
  end

  test "trashed children and trashed grants match the resolver" do
    kept = add_folder("Kept sibling")
    trashed = add_folder("Trashed child")
    grant(@user, :view, @root)
    trashed.update_column(:trashed_at, Time.current)

    assert_equal oracle_ids(@root), listed_ids(@root)
    refute_includes listed_ids(@root), trashed.id
    assert_includes listed_ids(@root), kept.id
    assert RecordingStudioAccessible.authorized?(actor: @user, recording: trashed, role: :view)

    grant_recording = grant(@user, :view, kept)
    revoke_root_grant
    assert_includes listed_ids(@root), kept.id

    grant_recording.update_column(:trashed_at, Time.current)

    assert_equal oracle_ids(@root), listed_ids(@root)
    refute_includes listed_ids(@root), kept.id
  end

  test "an unranked grant matches the blank floor and misses a ranked floor" do
    Folder.accessible_roles :view, :download
    ranked = add_folder("Ranked")
    download = add_folder("Download")
    grant(@user, :view, ranked)
    grant(@user, :download, download)

    assert_equal oracle_ids(@root), listed_ids(@root)
    assert_includes listed_ids(@root), download.id
    assert_equal oracle_ids(@root, minimum_role: :view), listed_ids(@root, minimum_role: :view)
    refute_includes listed_ids(@root, minimum_role: :view), download.id
  end

  test "a grant on a root off the parent path still includes that child" do
    other_workspace = Workspace.create!(name: "Parity Other Root")
    other_root = create_root_recording(other_workspace)
    other_bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(recording: other_root, actor: @user)
    assert other_bootstrap.success?, other_bootstrap.error.to_s

    parent = add_folder("Parent")
    off_path = add_page(parent, "Off path")
    sibling = add_page(parent, "Sibling")
    off_path.update_column(:root_recording_id, other_root.id)

    assert_equal oracle_ids(parent), listed_ids(parent)
    assert_includes listed_ids(parent), off_path.id
    refute_includes listed_ids(parent), sibling.id
  end

  test "grant queries stay batched as the child count grows" do
    4.times { |index| add_folder("Batch #{index}") }
    grant(@user, :view, @root)

    joins = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      next if payload[:cached] || payload[:name] == "SCHEMA"
      joins += 1 if sql.include?("INNER JOIN recording_studio_accesses")
    end

    ids = listed_ids(@root)
    assert_operator ids.length, :>=, 4
    assert_equal 2, joins
    assert_equal oracle_ids(@root), ids
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  private

  def listed_ids(parent, actor: @user, minimum_role: nil)
    RecordingStudioAccessible.recordings_for(
      actor: actor,
      parent_recording: parent,
      minimum_role: minimum_role
    ).pluck(:id).sort
  end

  def oracle_ids(parent, actor: @user, minimum_role: nil)
    kept_children(parent).select { |child| resolver_keeps?(child, actor, minimum_role) }.map(&:id).sort
  end

  def resolver_keeps?(child, actor, minimum_role)
    resolver = RecordingStudio::Services::AccessResolver.new(actor: actor, recording: child)
    return resolver.any_effective_grant? if minimum_role.blank?

    RecordingStudio::AccessRoles.satisfies?(role: resolver.resolve_role, minimum_role: minimum_role)
  end

  def kept_children(parent)
    RecordingStudio::Recording.unscoped.kept.where(parent_recording_id: parent.id).to_a
  end

  def rule_queries
    ActiveRecord::Base.connection.clear_query_cache
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
      sql = payload[:sql].to_s
      next if payload[:cached] || payload[:name] == "SCHEMA"
      count += 1 if sql.include?("recording_studio_access_rules")
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  def grant(actor, role, parent_recording)
    create_direct_access_recording(actor: actor, role: role, parent_recording: parent_recording)
  end

  def revoke_root_grant
    RecordingStudioAccessible.access_recordings_for_actor(recording: @root, actor: @user).each do |recording|
      recording.update_column(:trashed_at, Time.current)
    end
  end

  def add_folder(name, parent = @root)
    folder = Folder.create!(workspace: @workspace, name: name, summary: name, position: 0)
    create_child_recording(recordable: folder, parent_recording: parent)
  end

  def add_page(folder_recording, title = "Parity page")
    folder = folder_recording.recordable
    page = Page.create!(folder: folder, title: title, summary: "Page", position: 0)
    create_child_recording(recordable: page, parent_recording: folder_recording)
  end

  def configure_kit
    RecordingStudioAccessible.configuration.action_audiences[KIT] = {
      allowed: %i[public signed_in granted],
      default: :public,
      granted_roles: %i[view edit admin],
      granted_override: false,
      manage_role: :admin
    }
  end

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end
end
