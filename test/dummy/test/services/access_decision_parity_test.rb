# frozen_string_literal: true

require_relative "../test_helper"

# The batched repair, void, and audience writes must grant and deny the same
# actors as a full in-memory scan. Trashed grants stay out of both.
class AccessDecisionParityTest < ActiveSupport::TestCase
  KIT = :"parity.kit_download"

  setup do
    @original_audiences = RecordingStudioAccessible.configuration.action_audiences.to_h
    RecordingStudioAccessible.configuration.action_audiences.clear!
    RecordingStudioAccessible.configuration.action_audiences[KIT] = {
      allowed: %i[public signed_in granted],
      default: :public,
      granted_roles: %i[view edit admin],
      granted_override: false,
      manage_role: :admin
    }

    @admin = create_user("parity-admin@example.com")
    @editor = create_user("parity-editor@example.com")
    @outsider = create_user("parity-outsider@example.com")
    @dependent_actor = create_user("parity-dependent@example.com")
    @workspace = Workspace.create!(name: "Parity Workspace")
    @root = create_root_recording(@workspace)
    folder = Folder.create!(workspace: @workspace, name: "Parity Folder", summary: "Folder", position: 0)
    @folder = create_child_recording(recordable: folder, parent_recording: @root)
    page = Page.create!(folder: folder, title: "Parity Page", summary: "Page", position: 0)
    @page = create_child_recording(recordable: page, parent_recording: @folder)

    bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(recording: @root, actor: @admin)
    assert bootstrap.success?, bootstrap.error.to_s
    grant = RecordingStudioAccessible.grant_access(
      recording: @root, actor: @editor, role: :edit, manager_actor: @admin
    )
    assert grant.success?, grant.error.to_s
  end

  teardown do
    RecordingStudioAccessible.configuration.action_audiences.replace(@original_audiences)
  end

  test "duplicate repair matches a full scan across allow, deny, and trashed grants" do
    placeholder = create_user("parity-placeholder@example.com")
    live = create_direct_access_recording(actor: placeholder, role: :view, parent_recording: @folder)
    older = create_direct_access_recording(actor: @dependent_actor, role: :view, parent_recording: @folder)
    mutate_access!(live, actor: @editor, role: :view)
    mutate_access!(older, actor: @editor, role: :admin)
    trashed = create_direct_access_recording(actor: @outsider, role: :admin, parent_recording: @root)
    mutate_access!(trashed, actor: @editor, role: :admin)
    trashed.update_column(:trashed_at, Time.current)

    before = decisions
    reference = reference_duplicate_groups
    result = RecordingStudioAccessible::Services::AccessGrantIntegrity.call

    assert result.success?
    assert_equal reference, report_groups(result)
    assert_equal before, decisions
    assert_includes before.fetch(@editor.email).fetch(:folder), :edit
    assert_includes before.fetch(@editor.email).fetch(:page), :edit
    refute_includes before.fetch(@outsider.email).fetch(:folder), :view
    refute_includes before.fetch(@outsider.email).fetch(:page), :view
    refute_includes reference.flat_map { |group| group[:access_recording_ids] }, trashed.id
    assert live.persisted?
  end

  test "voiding dependents matches the effective check and leaves other grants" do
    manager = RecordingStudioAccessible.grant_access(
      recording: @folder, actor: @editor, role: :edit, manager_actor: @admin
    ).value
    effective = dependent_grant(actor: @dependent_actor, parent: @folder, manager: manager, role: :view)
    weak_manager = RecordingStudioAccessible.grant_access(
      recording: @folder, actor: @outsider, role: :view, manager_actor: @admin
    ).value
    doomed_actor = create_user("parity-doomed@example.com")
    doomed = dependent_grant(actor: doomed_actor, parent: @folder, manager: weak_manager, role: :view)
    weak_manager.update_column(:trashed_at, Time.current)
    trashed_admin = create_direct_access_recording(actor: @outsider, role: :admin, parent_recording: @root)
    trashed_admin.update_column(:trashed_at, Time.current)

    before = decisions
    reference = reference_void_ids(weak_manager.id)
    result = RecordingStudioAccessible::Services::VoidDependentAccesses.call(
      manager_access_recording_id: weak_manager.id,
      manager_actor: @admin
    )

    assert result.success?
    assert_equal reference.sort, result.value.sort
    assert_equal [doomed.id], reference
    refute_includes reference, effective.id
    assert_equal before, decisions
    assert RecordingStudioAccessible.authorized?(actor: @dependent_actor, recording: @page, role: :view)
    refute RecordingStudioAccessible.authorized?(actor: doomed_actor, recording: @page, role: :view)
    refute RecordingStudioAccessible.authorized?(actor: @outsider, recording: @root, role: :admin)
    assert RecordingStudioAccessible.authorized?(actor: @editor, recording: @folder, role: :edit)
    assert RecordingStudio::Recording.exists?(effective.id)
    assert_nil RecordingStudio::Recording.unscoped.find_by(id: doomed.id)
  end

  test "audience narrowing matches a per-rule rewrite and the same allow and deny" do
    other_folder = Folder.create!(workspace: @workspace, name: "Parity Kept", summary: "Kept", position: 2)
    other = create_child_recording(recordable: other_folder, parent_recording: @root)
    RecordingStudioAccessible.set_audience!(
      recording: @folder, action: KIT, audience: :public, actor: @admin
    )
    RecordingStudioAccessible.set_audience!(
      recording: other, action: KIT, audience: :granted, actor: @admin
    )
    kept_rule = RecordingStudioAccessible::AudienceQuery.rule_recording_for(recording: other, action: KIT)
    public_rule = RecordingStudioAccessible::AudienceQuery.rule_recording_for(recording: @folder, action: KIT)

    before_roles = decisions
    reference = reference_disallowed_rule_ids
    RecordingStudioAccessible.set_audience_constraint!(
      root: @root, action: KIT, allowed_audiences: %i[granted], actor: @admin
    )

    assert_equal [public_rule.id], reference
    assert_equal "granted", public_rule.reload.recordable.audience
    assert_equal "granted", kept_rule.reload.recordable.audience
    assert_equal before_roles, decisions
    assert RecordingStudioAccessible.authorized?(actor: @editor, recording: @folder, role: :edit)
    refute RecordingStudioAccessible.authorized?(actor: @outsider, recording: @folder, role: :view)
    assert RecordingStudioAccessible.authorized_action?(actor: @editor, action: KIT, recording: @folder)
    refute RecordingStudioAccessible.authorized_action?(actor: nil, action: KIT, recording: @folder)
    assert RecordingStudio::Event.where(recording_id: public_rule.id, action: "audience_fallback").exists?
    refute RecordingStudio::Event.where(recording_id: kept_rule.id, action: "audience_fallback").exists?
  end

  private

  def decisions
    [@admin, @editor, @outsider, @dependent_actor].to_h do |actor|
      [actor.email, {
        root: roles_held(actor, @root),
        folder: roles_held(actor, @folder),
        page: roles_held(actor, @page)
      }]
    end
  end

  def roles_held(actor, recording)
    %i[view edit admin].select do |role|
      RecordingStudioAccessible.authorized?(actor: actor, recording: recording, role: role)
    end
  end

  def reference_duplicate_groups
    scope = RecordingStudio::Recording.unscoped.where(recordable_type: "RecordingStudio::Access")
    scope = scope.where(RecordingStudio::Recording.recording_studio_trashable_kept_sql)
    recordings = scope.joins(RecordingStudioAccessible::DirectAccessQuery::ACCESS_JOIN_SQL)
                      .includes(:recordable)
                      .order(created_at: :desc, id: :desc)
                      .to_a
    recordings.group_by { |recording| reference_group_key(recording) }
              .select { |_key, rows| rows.length > 1 }
              .map { |key, rows| reference_group(key, rows) }
  end

  def reference_group_key(recording)
    access = recording.recordable
    actor = access.actor
    type = actor ? RecordingStudioAccessible::ActorType.for(actor) : access.actor_type
    [recording.parent_recording_id, type, access.actor_id]
  end

  def reference_group(key, rows)
    roles = rows.map { |recording| recording.recordable.role }
    strongest = roles.select { |role| RecordingStudio::AccessRoles.value_for(role) }
                     .max_by { |role| RecordingStudio::AccessRoles.value_for(role) }
    {
      parent_recording_id: key[0],
      actor_type: key[1],
      actor_id: key[2],
      access_recording_ids: rows.map(&:id),
      roles: roles,
      strongest_role: strongest
    }
  end

  def report_groups(result)
    result.value.fetch(:report).map do |entry|
      entry.slice(:parent_recording_id, :actor_type, :actor_id, :access_recording_ids, :roles, :strongest_role)
    end
  end

  def reference_void_ids(manager_id)
    ids = []
    RecordingStudioAccessible::DirectAccessQuery.access_recordings_depending_on(manager_id).find_each do |recording|
      ids << recording.id unless RecordingStudioAccessible::DependentAccess.effective?(recording)
    end
    ids
  end

  def reference_disallowed_rule_ids
    allowed = %i[granted]
    ids = []
    RecordingStudioAccessible::AudienceQuery.descendant_rule_recordings(root: @root, action: KIT).find_each do |rule|
      current = rule.recordable.audience.to_s.strip.to_sym
      ids << rule.id unless allowed.include?(current)
    end
    ids
  end

  def dependent_grant(actor:, parent:, manager:, role:)
    result = RecordingStudioAccessible.grant_access(
      recording: parent,
      actor: actor,
      role: role,
      manager_actor: @admin,
      depends_on: manager
    )
    assert result.success?, result.error.to_s
    result.value
  end

  def mutate_access!(access_recording, actor:, role:)
    connection = ActiveRecord::Base.connection
    connection.execute(<<~SQL.squish)
      UPDATE recording_studio_accesses
      SET actor_type = #{connection.quote(RecordingStudioAccessible::ActorType.for(actor))},
          actor_id = #{connection.quote(actor.id)},
          role = #{connection.quote(role.to_s)}
      WHERE id = #{connection.quote(access_recording.recordable_id)}
    SQL
  end

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end
end
