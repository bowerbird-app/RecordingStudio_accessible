# frozen_string_literal: true

require_relative "../test_helper"

class AudienceRulesTest < ActiveSupport::TestCase
  KIT = :"presskits.kit_download"
  EXPORT = :"account.private_data_export"

  setup do
    @original_action_registry = RecordingStudioAccessible.instance_variable_get(:@action_registry)
    @original_audience_registry = RecordingStudioAccessible.instance_variable_get(:@audience_registry)
    @original_action_audiences = RecordingStudioAccessible.configuration.action_audiences.to_h
    RecordingStudioAccessible.instance_variable_set(:@action_registry, RecordingStudioAccessible::ActionRegistry.new)
    RecordingStudioAccessible.instance_variable_set(:@audience_registry, RecordingStudioAccessible::AudienceRegistry.new)
    RecordingStudioAccessible.configuration.action_audiences.clear!

    @admin = create_user("audience-admin@example.com")
    @editor = create_user("audience-editor@example.com")
    @outsider = create_user("audience-outsider@example.com")

    @workspace = Workspace.create!(name: "Audience Workspace")
    @root = create_root_recording(@workspace)
    @folder = Folder.create!(workspace: @workspace, name: "Kits", summary: "Press kits", position: 0)
    @folder_recording = create_child_recording(recordable: @folder, parent_recording: @root)

    bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(recording: @root, actor: @admin)
    assert bootstrap.success?, bootstrap.error.to_s
    grant = RecordingStudioAccessible.grant_access(
      recording: @root,
      actor: @editor,
      role: :edit,
      manager_actor: @admin
    )
    assert grant.success?, grant.error.to_s

    configure_kit
  end

  teardown do
    RecordingStudioAccessible.instance_variable_set(:@action_registry, @original_action_registry)
    RecordingStudioAccessible.instance_variable_set(:@audience_registry, @original_audience_registry)
    RecordingStudioAccessible.configuration.action_audiences.replace(@original_action_audiences)
  end

  test "constraint relaxation rewrites rules to granted and never restores public" do
    RecordingStudioAccessible.set_audience!(
      recording: @folder_recording,
      action: KIT,
      audience: :public,
      actor: @admin
    )

    assert_equal :public, RecordingStudioAccessible.effective_audience(recording: @folder_recording, action: KIT)

    RecordingStudioAccessible.set_audience_constraint!(
      root: @root,
      action: KIT,
      allowed_audiences: %i[granted],
      actor: @admin
    )

    rule = RecordingStudioAccessible::AudienceQuery.rule_recording_for(recording: @folder_recording, action: KIT)
    assert_equal "granted", rule.recordable.audience
    assert_equal :granted, RecordingStudioAccessible.effective_audience(recording: @folder_recording, action: KIT)
    assert RecordingStudio::Event.where(recording_id: rule.id, action: "audience_fallback").exists?
    assert RecordingStudio::Event.where(recording_id: rule.id, action: "updated").exists?

    RecordingStudioAccessible.set_audience_constraint!(
      root: @root,
      action: KIT,
      allowed_audiences: %i[public signed_in granted],
      actor: @admin
    )

    rule.reload
    assert_equal "granted", rule.recordable.audience
    assert_equal :granted, RecordingStudioAccessible.effective_audience(recording: @folder_recording, action: KIT)
  end

  test "workspace and action isolation" do
    other_workspace = Workspace.create!(name: "Other Audience Workspace")
    other_root = create_root_recording(other_workspace)
    other_bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(recording: other_root, actor: @admin)
    assert other_bootstrap.success?, other_bootstrap.error.to_s
    RecordingStudioAccessible.configuration.action_audiences[EXPORT] = {
      allowed: %i[granted],
      default: :granted,
      granted_roles: %i[admin]
    }

    RecordingStudioAccessible.set_audience!(
      recording: @folder_recording,
      action: KIT,
      audience: :public,
      actor: @admin
    )
    RecordingStudioAccessible.set_audience_constraint!(
      root: @root,
      action: KIT,
      allowed_audiences: %i[granted],
      actor: @admin
    )

    assert_equal :granted, RecordingStudioAccessible.effective_audience(recording: @folder_recording, action: KIT)
    assert_equal :public, RecordingStudioAccessible.effective_audience(recording: other_root, action: KIT)
    assert_equal :granted, RecordingStudioAccessible.effective_audience(recording: @folder_recording, action: EXPORT)
    assert RecordingStudioAccessible.authorized_action?(actor: nil, action: KIT, recording: other_root)
    refute RecordingStudioAccessible.authorized_action?(actor: nil, action: KIT, recording: @folder_recording)
    refute RecordingStudioAccessible.authorized_action?(actor: nil, action: EXPORT, recording: @folder_recording)
  end

  test "settings changes require manage_role and root admin" do
    error = assert_raises(RecordingStudioAccessible::AudienceUnauthorized) do
      RecordingStudioAccessible.set_audience!(
        recording: @folder_recording,
        action: KIT,
        audience: :public,
        actor: @editor
      )
    end
    assert_equal RecordingStudioAccessible::Copy.t("errors.audience_unauthorized"), error.message

    RecordingStudioAccessible.set_audience!(
      recording: @folder_recording,
      action: KIT,
      audience: :public,
      actor: @admin
    )

    error = assert_raises(RecordingStudioAccessible::AudienceUnauthorized) do
      RecordingStudioAccessible.set_audience_constraint!(
        root: @root,
        action: KIT,
        allowed_audiences: %i[granted],
        actor: @editor
      )
    end
    assert_equal RecordingStudioAccessible::Copy.t("errors.audience_constraint_unauthorized"), error.message

    error = assert_raises(RecordingStudioAccessible::AudienceUnauthorized) do
      RecordingStudioAccessible.set_audience_constraint!(
        root: @root,
        action: KIT,
        allowed_audiences: %i[granted],
        actor: @outsider
      )
    end
    assert_equal RecordingStudioAccessible::Copy.t("errors.audience_constraint_unauthorized"), error.message
  end

  test "set_audience raises when the audience is not currently allowed" do
    RecordingStudioAccessible.set_audience_constraint!(
      root: @root,
      action: KIT,
      allowed_audiences: %i[granted],
      actor: @admin
    )

    error = assert_raises(RecordingStudioAccessible::AudienceNotAllowed) do
      RecordingStudioAccessible.set_audience!(
        recording: @folder_recording,
        action: KIT,
        audience: :public,
        actor: @admin
      )
    end
    assert_equal RecordingStudioAccessible::Copy.t("errors.audience_not_allowed"), error.message
  end

  test "constraint cannot widen past host allowed" do
    RecordingStudioAccessible.configuration.action_audiences[KIT] = {
      allowed: %i[signed_in granted],
      default: :granted,
      granted_roles: %i[view edit admin],
      manage_role: :admin
    }

    error = assert_raises(RecordingStudioAccessible::AudienceNotAllowed) do
      RecordingStudioAccessible.set_audience_constraint!(
        root: @root,
        action: KIT,
        allowed_audiences: %i[public granted],
        actor: @admin
      )
    end
    assert_equal RecordingStudioAccessible::Copy.t("errors.audience_constraint_not_narrower"), error.message
  end

  test "constraint is rejected on a non-root recording" do
    error = assert_raises(RecordingStudioAccessible::AudienceInvalid) do
      RecordingStudioAccessible.set_audience_constraint!(
        root: @folder_recording,
        action: KIT,
        allowed_audiences: %i[granted],
        actor: @admin
      )
    end
    assert_equal RecordingStudioAccessible::Copy.t("errors.audience_constraint_not_root"), error.message
  end

  test "direct access constraint and rule creation is blocked" do
    assert_no_difference -> { RecordingStudio::AccessRule.count } do
      error = assert_raises(ActiveRecord::RecordInvalid) do
        RecordingStudio::AccessRule.create!(action: KIT.to_s, audience: "public")
      end
      assert_includes error.record.errors.full_messages.join, "Create audiences through"
    end

    assert_no_difference -> { RecordingStudio::AccessConstraint.count } do
      error = assert_raises(ActiveRecord::RecordInvalid) do
        RecordingStudio::AccessConstraint.create!(action: KIT.to_s, allowed_audiences: ["granted"])
      end
      assert_includes error.record.errors.full_messages.join, "Create audience limits through"
    end
  end

  test "at most one live rule per action per recording with history on revise" do
    first = RecordingStudioAccessible.set_audience!(
      recording: @folder_recording,
      action: KIT,
      audience: :public,
      actor: @admin
    )
    second = RecordingStudioAccessible.set_audience!(
      recording: @folder_recording,
      action: KIT,
      audience: :signed_in,
      actor: @admin
    )

    assert_equal first.id, second.id
    assert_equal "signed_in", second.recordable.audience
    refute_equal first.recordable_id, second.recordable_id
    assert_equal 1, RecordingStudioAccessible::AudienceQuery.descendant_rule_recordings(root: @root, action: KIT).count
    assert RecordingStudio::Event.where(recording_id: second.id, action: "updated").exists?
    assert RecordingStudio::Event.where(recording_id: second.id, action: "created").exists?
  end

  test "trashed rules are ignored by resolution" do
    rule = RecordingStudioAccessible.set_audience!(
      recording: @folder_recording,
      action: KIT,
      audience: :signed_in,
      actor: @admin
    )
    rule.update_column(:trashed_at, Time.current)

    assert_equal :public, RecordingStudioAccessible.effective_audience(recording: @folder_recording, action: KIT)
  end

  test "granted users pass granted audience and public still allows anonymous" do
    RecordingStudioAccessible.set_audience!(
      recording: @folder_recording,
      action: KIT,
      audience: :granted,
      actor: @admin
    )

    refute RecordingStudioAccessible.authorized_action?(actor: nil, action: KIT, recording: @folder_recording)
    refute RecordingStudioAccessible.authorized_action?(actor: @outsider, action: KIT, recording: @folder_recording)
    assert RecordingStudioAccessible.authorized_action?(actor: @editor, action: KIT, recording: @folder_recording)
    assert RecordingStudioAccessible.authorized_action?(actor: @admin, action: KIT, recording: @folder_recording)

    RecordingStudioAccessible.set_audience!(
      recording: @folder_recording,
      action: KIT,
      audience: :public,
      actor: @admin
    )
    assert RecordingStudioAccessible.authorized_action?(actor: nil, action: KIT, recording: @folder_recording)
  end

  test "custom manage_role is required to change the recording audience" do
    RecordingStudioAccessible.configuration.action_audiences[KIT] = {
      allowed: %i[public signed_in granted],
      default: :public,
      granted_roles: %i[view edit admin],
      manage_role: :edit
    }

    RecordingStudioAccessible.set_audience!(
      recording: @folder_recording,
      action: KIT,
      audience: :signed_in,
      actor: @editor
    )
    assert_equal :signed_in, RecordingStudioAccessible.effective_audience(recording: @folder_recording, action: KIT)
  end

  test "recordable declarations include audience types on opted-in parents" do
    assert_includes RecordingStudio.configuration.recordable_types, "RecordingStudio::AccessConstraint"
    assert_includes RecordingStudio.configuration.recordable_types, "RecordingStudio::AccessRule"
    refute RecordingStudio.root_allowed?(RecordingStudio::AccessConstraint)
    refute RecordingStudio.root_allowed?(RecordingStudio::AccessRule)
    assert_equal %w[RecordingStudio::AccessConstraint RecordingStudio::AccessRule],
                 RecordingStudio.capability_child_recordables_for(:action_audiences)
  end

  private

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
