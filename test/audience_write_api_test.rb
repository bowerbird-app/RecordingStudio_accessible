# frozen_string_literal: true

require "test_helper"

class AudienceWriteApiTest < Minitest::Test
  KIT = :"presskits.kit_download"

  def setup
    @original_action_registry = RecordingStudioAccessible.instance_variable_get(:@action_registry)
    @original_audience_registry = RecordingStudioAccessible.instance_variable_get(:@audience_registry)
    @original_action_audiences = RecordingStudioAccessible.configuration.action_audiences.to_h
    RecordingStudioAccessible.instance_variable_set(:@action_registry, RecordingStudioAccessible::ActionRegistry.new)
    RecordingStudioAccessible.instance_variable_set(:@audience_registry, RecordingStudioAccessible::AudienceRegistry.new)
    RecordingStudioAccessible.configuration.action_audiences.clear!
    RecordingStudioAccessible.configuration.action_audiences[KIT] = {
      allowed: %i[public signed_in granted],
      default: :public,
      granted_roles: %i[view edit admin],
      manage_role: :admin
    }
  end

  def teardown
    RecordingStudioAccessible.instance_variable_set(:@action_registry, @original_action_registry)
    RecordingStudioAccessible.instance_variable_set(:@audience_registry, @original_audience_registry)
    RecordingStudioAccessible.configuration.action_audiences.replace(@original_action_audiences)
  end

  def test_set_audience_requires_a_recording
    error = assert_raises(RecordingStudioAccessible::AudienceInvalid) do
      RecordingStudioAccessible.set_audience!(recording: nil, action: KIT, audience: :public, actor: :actor)
    end

    assert_equal RecordingStudioAccessible::Copy.t("errors.recording_required"), error.message
  end

  def test_set_audience_requires_a_configured_action
    error = assert_raises(RecordingStudioAccessible::AudienceInvalid) do
      RecordingStudioAccessible.set_audience!(
        recording: recording_stub,
        action: :missing,
        audience: :public,
        actor: actor_stub
      )
    end

    assert_equal RecordingStudioAccessible::Copy.t("errors.audience_action_not_configured"), error.message
  end

  def test_set_audience_requires_a_symbol_action
    error = assert_raises(RecordingStudioAccessible::AudienceInvalid) do
      RecordingStudioAccessible.set_audience!(
        recording: recording_stub,
        action: "presskits.kit_download",
        audience: :public,
        actor: actor_stub
      )
    end

    assert_equal RecordingStudioAccessible::Copy.t("errors.audience_action_invalid"), error.message
  end

  def test_set_audience_requires_manage_role
    error = assert_raises(RecordingStudioAccessible::AudienceUnauthorized) do
      RecordingStudioAccessible.set_audience!(
        recording: recording_stub,
        action: KIT,
        audience: :public,
        actor: nil
      )
    end

    assert_equal RecordingStudioAccessible::Copy.t("errors.audience_unauthorized"), error.message
  end

  def test_set_audience_constraint_requires_a_root
    error = assert_raises(RecordingStudioAccessible::AudienceInvalid) do
      RecordingStudioAccessible.set_audience_constraint!(
        root: nil,
        action: KIT,
        allowed_audiences: %i[granted],
        actor: :actor
      )
    end

    assert_equal RecordingStudioAccessible::Copy.t("errors.audience_root_required"), error.message
  end

  def test_set_audience_constraint_rejects_non_roots
    RecordingStudio.stub(:root_recording?, false) do
      error = assert_raises(RecordingStudioAccessible::AudienceInvalid) do
        RecordingStudioAccessible.set_audience_constraint!(
          root: recording_stub,
          action: KIT,
          allowed_audiences: %i[granted],
          actor: actor_stub
        )
      end

      assert_equal RecordingStudioAccessible::Copy.t("errors.audience_constraint_not_root"), error.message
    end
  end

  def test_granted_roles_for_and_manage_role_read_config
    assert_equal %w[view edit admin], RecordingStudioAccessible.granted_roles_for(KIT)
    assert_equal :admin, RecordingStudioAccessible::AudienceResolver.manage_role_for(KIT)
    refute RecordingStudioAccessible::AudienceResolver.granted_override?(KIT)
  end

  def recording_stub
    Struct.new(:id).new("recording-id")
  end

  def actor_stub
    Struct.new(:id).new("actor-id")
  end

  def test_action_audiences_replace_installs_policies
    RecordingStudioAccessible.configuration.action_audiences = {
      KIT => { allowed: %i[granted], default: :granted, granted_roles: %i[admin] }
    }

    assert RecordingStudioAccessible.action_defined?(KIT)
    assert_equal %i[granted], RecordingStudioAccessible.configuration.action_audiences[KIT].fetch(:allowed)
  end
end
