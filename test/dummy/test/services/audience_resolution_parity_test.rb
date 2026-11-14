# frozen_string_literal: true

require_relative "../test_helper"

# Root audience loads must allow and deny the same actors as a per-recording
# rule read. Trashed rules and grants stay out of both.
class AudienceResolutionParityTest < ActiveSupport::TestCase
  KIT = :"presskits.kit_download"

  setup do
    @original_action_audiences = RecordingStudioAccessible.configuration.action_audiences.to_h
    configure_kit

    @admin = create_user("audience-resolve-admin@example.com")
    @editor = create_user("audience-resolve-editor@example.com")
    @outsider = create_user("audience-resolve-outsider@example.com")
    @dependent_actor = create_user("audience-resolve-dependent@example.com")
    @workspace = Workspace.create!(name: "Audience Resolve Workspace")
    @root = create_root_recording(@workspace)
    bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(recording: @root, actor: @admin)
    assert bootstrap.success?, bootstrap.error.to_s
    grant(@editor, :edit, @root)
  end

  teardown do
    RecordingStudioAccessible.configuration.action_audiences.replace(@original_action_audiences)
  end

  test "public allows and granted denies the same actors as a per-recording read" do
    public_folder = add_folder("Public")
    granted_folder = add_folder("Granted")
    RecordingStudioAccessible.set_audience!(recording: public_folder, action: KIT, audience: :public, actor: @admin)
    RecordingStudioAccessible.set_audience!(recording: granted_folder, action: KIT, audience: :granted, actor: @admin)

    assert_equal :public, audience_for(public_folder)
    assert authorized_for(nil, public_folder)
    assert authorized_for(@outsider, public_folder)

    assert_equal :granted, audience_for(granted_folder)
    refute authorized_for(nil, granted_folder)
    refute authorized_for(@outsider, granted_folder)
    assert authorized_for(@editor, granted_folder)

    assert_matches_legacy(public_folder)
    assert_matches_legacy(granted_folder)
  end

  test "a narrowed audience matches a per-recording read" do
    folder = add_folder("Narrowed")
    RecordingStudioAccessible.set_audience!(recording: folder, action: KIT, audience: :public, actor: @admin)
    configure_kit(allowed: %i[granted], default: :granted)

    assert_equal :granted, audience_for(folder)
    refute authorized_for(nil, folder)
    refute authorized_for(@outsider, folder)
    assert authorized_for(@editor, folder)
    assert_matches_legacy(folder)

    configure_kit
    other = add_folder("Kept granted")
    RecordingStudioAccessible.set_audience!(recording: other, action: KIT, audience: :granted, actor: @admin)
    RecordingStudioAccessible.set_audience_constraint!(
      root: @root, action: KIT, allowed_audiences: %i[granted], actor: @admin
    )

    assert_equal :granted, audience_for(folder)
    assert_equal :granted, audience_for(other)
    refute authorized_for(nil, folder)
    assert authorized_for(@editor, folder)
    assert_matches_legacy(folder)
    assert_matches_legacy(other)
  end

  test "a dependent grant matches a per-recording read when the manager is trashed" do
    folder = add_folder("Dependent")
    RecordingStudioAccessible.set_audience!(recording: folder, action: KIT, audience: :granted, actor: @admin)
    manager = grant(@editor, :edit, folder)
    grant(@dependent_actor, :view, folder, depends_on: manager)

    assert authorized_for(@dependent_actor, folder)
    refute authorized_for(@outsider, folder)
    assert_matches_legacy(folder)

    manager.update_column(:trashed_at, Time.current)

    refute authorized_for(@dependent_actor, folder)
    assert authorized_for(@editor, folder)
    assert_matches_legacy(folder)
  end

  test "a trashed rule and a trashed recording match a per-recording read" do
    kept = add_folder("Kept")
    trashed = add_folder("Trashed folder")
    RecordingStudioAccessible.set_audience!(recording: kept, action: KIT, audience: :granted, actor: @admin)
    RecordingStudioAccessible.set_audience!(recording: trashed, action: KIT, audience: :public, actor: @admin)
    trashed.update_column(:trashed_at, Time.current)

    assert_equal :granted, audience_for(kept)
    assert_equal :public, audience_for(trashed)
    refute authorized_for(nil, kept)
    assert authorized_for(nil, trashed)
    assert_matches_legacy(kept)
    assert_matches_legacy(trashed)

    rule = RecordingStudioAccessible::AudienceQuery.rule_recording_for(recording: kept, action: KIT)
    rule.update_column(:trashed_at, Time.current)

    assert_equal :public, audience_for(kept)
    assert authorized_for(nil, kept)
    refute_equal trashed.id, kept.id
    assert_matches_legacy(kept)
  end

  test "one root does not reuse another root's rules" do
    folder = add_folder("This root")
    RecordingStudioAccessible.set_audience!(recording: folder, action: KIT, audience: :granted, actor: @admin)
    other_workspace = Workspace.create!(name: "Audience Resolve Other")
    other_root = create_root_recording(other_workspace)
    other_bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(recording: other_root, actor: @admin)
    assert other_bootstrap.success?, other_bootstrap.error.to_s
    other_folder = Folder.create!(workspace: other_workspace, name: "Other", summary: "Other", position: 0)
    other = create_child_recording(recordable: other_folder, parent_recording: other_root)
    RecordingStudioAccessible.set_audience!(recording: other, action: KIT, audience: :public, actor: @admin)

    with_query_cache do
      assert_equal :granted, audience_for(folder)
      assert_equal :public, audience_for(other)
      assert_equal :granted, audience_for(folder)
      assert_matches_legacy(folder)
      assert_matches_legacy(other)
    end
  end

  test "a write clears the shared root read" do
    folder = add_folder("Cached rule")
    configure_kit(default: :signed_in)
    RecordingStudioAccessible.set_audience!(recording: folder, action: KIT, audience: :public, actor: @admin)

    with_query_cache do
      assert_equal :public, audience_for(folder)
      rule = RecordingStudioAccessible::AudienceQuery.rule_recording_for(recording: folder, action: KIT)
      rule.update_column(:trashed_at, Time.current)

      assert_equal :signed_in, audience_for(folder)
      refute authorized_for(nil, folder)
      assert authorized_for(@outsider, folder)
      assert_matches_legacy(folder)
    end
  end

  test "query count stays flat as recordings grow" do
    folders = Array.new(6) do |index|
      folder = add_folder("Batch #{index}")
      RecordingStudioAccessible.set_audience!(recording: folder, action: KIT, audience: :public, actor: @admin)
      folder
    end
    folders.each { |folder| audience_for(folder) }

    small = nil
    large = nil
    with_query_cache do
      small = query_counts { folders.first(2).each { |folder| check_folder(folder) } }
      large = query_counts { folders.each { |folder| check_folder(folder) } }
    end

    assert_equal small, large, "queries scaled: 2 recordings #{small.inspect}, 6 recordings #{large.inspect}"
    assert_operator large[:total], :<, folders.size
    assert_operator large[:rules], :<, folders.size
  end

  private

  def assert_matches_legacy(recording, actors = [nil, @outsider, @editor, @dependent_actor])
    legacy = legacy_snapshot(recording)
    assert_equal legacy_audience(recording, legacy), audience_for(recording)
    actors.each do |actor|
      assert_equal legacy_authorized(actor, recording, legacy), authorized_for(actor, recording)
    end
  end

  def check_folder(folder)
    audience_for(folder)
    authorized_for(nil, folder)
    authorized_for(@outsider, folder)
  end

  def audience_for(recording)
    RecordingStudioAccessible.effective_audience(recording: recording, action: KIT)
  end

  def authorized_for(actor, recording)
    RecordingStudioAccessible.authorized_action?(actor: actor, action: KIT, recording: recording)
  end

  def legacy_audience(recording, snapshot)
    RecordingStudioAccessible::AudienceResolver.effective_audience(
      recording: recording, action: KIT, snapshot: snapshot
    )
  end

  def legacy_authorized(actor, recording, snapshot)
    RecordingStudioAccessible::AudienceAuthorization.authorized?(
      actor: actor, action: KIT, recording: recording, snapshot: snapshot
    )
  end

  def legacy_snapshot(recording)
    root = RecordingStudio.root_recording_or_self(recording)
    rows = [
      RecordingStudioAccessible::AudienceQuery.rule_recording_for(recording: recording, action: KIT),
      RecordingStudioAccessible::AudienceQuery.constraint_recording_for(root: root, action: KIT)
    ]
    RecordingStudioAccessible::AudienceSnapshot.new(rows.compact)
  end

  def query_counts
    ActiveRecord::Base.connection.clear_query_cache
    total = 0
    rules = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
      payload = ActiveSupport::Notifications::Event.new(*args).payload
      sql = payload[:sql].to_s
      next if payload[:cached] || payload[:name] == "SCHEMA"
      next if sql.match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE|SHOW|SET)\b/i)

      total += 1
      rules += 1 if sql.include?("recording_studio_access_rules") || sql.include?("recording_studio_access_constraints")
    end
    yield
    { total: total, rules: rules }
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  def with_query_cache(&)
    ActiveRecord::Base.connection_pool.enable_query_cache(&)
  end

  def configure_kit(allowed: %i[public signed_in granted], default: :public)
    RecordingStudioAccessible.configuration.action_audiences[KIT] = {
      allowed: allowed,
      default: default,
      granted_roles: %i[view edit admin],
      granted_override: false,
      manage_role: :admin
    }
  end

  def add_folder(name)
    folder = Folder.create!(workspace: @workspace, name: name, summary: name, position: 0)
    create_child_recording(recordable: folder, parent_recording: @root)
  end

  def grant(actor, role, parent, depends_on: nil)
    result = RecordingStudioAccessible.grant_access(
      recording: parent,
      actor: actor,
      role: role,
      manager_actor: @admin,
      depends_on: depends_on
    )
    assert result.success?, result.error.to_s
    result.value
  end

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end
end
