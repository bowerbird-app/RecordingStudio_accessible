# frozen_string_literal: true

require "test_helper"

class ActionAudiencesTest < Minitest::Test
  KIT = :"presskits.kit_download"
  EXPORT = :"account.private_data_export"

  def setup
    @original_action_registry = RecordingStudioAccessible.instance_variable_get(:@action_registry)
    @original_audience_registry = RecordingStudioAccessible.instance_variable_get(:@audience_registry)
    @original_action_audiences = RecordingStudioAccessible.configuration.action_audiences.to_h
    RecordingStudioAccessible.instance_variable_set(:@action_registry, RecordingStudioAccessible::ActionRegistry.new)
    RecordingStudioAccessible.instance_variable_set(:@audience_registry, RecordingStudioAccessible::AudienceRegistry.new)
    RecordingStudioAccessible.configuration.action_audiences.clear!
  end

  def teardown
    RecordingStudioAccessible.instance_variable_set(:@action_registry, @original_action_registry)
    RecordingStudioAccessible.instance_variable_set(:@audience_registry, @original_audience_registry)
    RecordingStudioAccessible.configuration.action_audiences.replace(@original_action_audiences)
  end

  def test_granted_is_always_kept_in_the_allowed_set
    configure_kit(allowed: %i[public], default: :public, granted_roles: %i[download])

    allowed = RecordingStudioAccessible::AudienceResolver.allowed_audiences_for(
      recording: :recording,
      action: KIT
    )

    assert_includes allowed, :granted
    assert_includes allowed, :public
  end

  def test_no_valid_granted_roles_resolves_to_denied
    configure_kit(allowed: %i[public granted], default: :public, granted_roles: [])

    assert_equal :denied, RecordingStudioAccessible.effective_audience(recording: :recording, action: KIT)
    refute RecordingStudioAccessible.authorized_action?(actor: nil, action: KIT, recording: :recording)
  end

  def test_missing_action_audiences_config_does_not_change_existing_action_api
    RecordingStudioAccessible.define_action(:subscribed) { true }

    assert RecordingStudioAccessible.authorized_action?(actor: :actor, action: :subscribed)
    refute RecordingStudioAccessible.authorized_action?(actor: :actor, action: :missing)
    assert_equal :denied, RecordingStudioAccessible.effective_audience(recording: :recording, action: KIT)
  end

  def test_invalid_config_denies
    RecordingStudioAccessible.configuration.action_audiences[KIT] = {
      allowed: %i[public not_a_real_audience],
      default: :public,
      granted_roles: %i[download]
    }

    assert_equal :denied, RecordingStudioAccessible.effective_audience(recording: :recording, action: KIT)
    refute RecordingStudioAccessible.authorized_action?(actor: :actor, action: KIT, recording: :recording)
  end

  def test_unknown_audience_stored_rule_denies
    configure_kit(allowed: %i[public granted], default: :public, granted_roles: %i[view])
    rule = rule_recording(audience: :not_registered)

    RecordingStudioAccessible::AudienceQuery.stub(:rule_recording_for, rule) do
      RecordingStudioAccessible::AudienceQuery.stub(:constraint_recording_for, nil) do
        assert_equal :denied, RecordingStudioAccessible.effective_audience(recording: :recording, action: KIT)
      end
    end
  end

  def test_disallowed_stored_audience_falls_back_to_granted
    configure_kit(allowed: %i[signed_in granted], default: :granted, granted_roles: %i[view])
    rule = rule_recording(audience: :public)

    RecordingStudioAccessible::AudienceQuery.stub(:rule_recording_for, rule) do
      RecordingStudioAccessible::AudienceQuery.stub(:constraint_recording_for, nil) do
        assert_equal :granted, RecordingStudioAccessible.effective_audience(recording: :recording, action: KIT)
      end
    end
  end

  def test_host_default_used_when_no_stored_rule
    configure_kit(allowed: %i[public signed_in granted], default: :signed_in, granted_roles: %i[view])

    assert_equal :signed_in, RecordingStudioAccessible.effective_audience(recording: :recording, action: KIT)
  end

  def test_default_outside_allowed_set_falls_back_to_granted
    configure_kit(allowed: %i[granted], default: :public, granted_roles: %i[view])

    assert_equal :granted, RecordingStudioAccessible.effective_audience(recording: :recording, action: KIT)
  end

  def test_nil_recording_denies_audience_actions
    configure_kit

    refute RecordingStudioAccessible.authorized_action?(actor: :actor, action: KIT)
    refute RecordingStudioAccessible.authorized_action?(actor: nil, action: KIT, recording: nil)
  end

  def test_public_allows_nil_actor
    configure_kit(allowed: %i[public granted], default: :public, granted_roles: %i[view])

    assert RecordingStudioAccessible.authorized_action?(actor: nil, action: KIT, recording: :recording)
  end

  def test_signed_in_denies_nil_actor
    configure_kit(allowed: %i[signed_in granted], default: :signed_in, granted_roles: %i[view])

    refute RecordingStudioAccessible.authorized_action?(actor: nil, action: KIT, recording: :recording)
    assert RecordingStudioAccessible.authorized_action?(actor: :actor, action: KIT, recording: :recording)
  end

  def test_granted_audience_uses_granted_roles_not_any_role
    configure_kit(allowed: %i[granted], default: :granted, granted_roles: %i[download edit admin])
    viewer = Object.new
    editor = Object.new

    RecordingStudioAccessible.stub(:authorized_for_any_role?, lambda { |**kwargs|
      kwargs[:actor].equal?(editor) && kwargs[:roles] == %w[download edit admin]
    }) do
      refute RecordingStudioAccessible.authorized_action?(actor: viewer, action: KIT, recording: :recording)
      assert RecordingStudioAccessible.authorized_action?(actor: editor, action: KIT, recording: :recording)
    end
  end

  def test_granted_override_on_allows_granted_actor_for_other_audiences
    RecordingStudioAccessible.register_audience(:verified) { false }
    configure_kit(
      allowed: %i[verified granted],
      default: :verified,
      granted_roles: %i[download],
      granted_override: true
    )
    actor = Object.new

    RecordingStudioAccessible.stub(:authorized_for_any_role?, lambda { |**kwargs|
      kwargs[:actor].equal?(actor) && kwargs[:roles] == ["download"]
    }) do
      assert RecordingStudioAccessible.authorized_action?(actor: actor, action: KIT, recording: :recording)
    end
  end

  def test_granted_override_off_does_not_let_granted_actor_skip_audience
    RecordingStudioAccessible.register_audience(:verified) { false }
    configure_kit(
      allowed: %i[verified granted],
      default: :verified,
      granted_roles: %i[download],
      granted_override: false
    )
    actor = Object.new

    RecordingStudioAccessible.stub(:authorized_for_any_role?, true) do
      refute RecordingStudioAccessible.authorized_action?(actor: actor, action: KIT, recording: :recording)
    end
  end

  def test_custom_audience_predicate_exception_denies
    RecordingStudioAccessible.register_audience(:exploding) { raise "boom" }
    configure_kit(allowed: %i[exploding granted], default: :exploding, granted_roles: %i[view])

    refute RecordingStudioAccessible.authorized_action?(actor: :actor, action: KIT, recording: :recording)
  end

  def test_auto_supplies_define_action_policy
    configure_kit(allowed: %i[public granted], default: :public, granted_roles: %i[view])

    assert RecordingStudioAccessible.action_defined?(KIT)
    assert RecordingStudioAccessible.registered_action?(KIT)
    assert RecordingStudioAccessible.action_registration_for(KIT).fetch(:recording_required)
  end

  def test_action_isolation_between_configured_actions
    configure_kit(allowed: %i[public granted], default: :public, granted_roles: %i[view])
    RecordingStudioAccessible.configuration.action_audiences[EXPORT] = {
      allowed: %i[granted],
      default: :granted,
      granted_roles: %i[admin],
      granted_override: false
    }

    assert_equal :public, RecordingStudioAccessible.effective_audience(recording: :recording, action: KIT)
    assert_equal :granted, RecordingStudioAccessible.effective_audience(recording: :recording, action: EXPORT)
    assert RecordingStudioAccessible.authorized_action?(actor: nil, action: KIT, recording: :recording)
    refute RecordingStudioAccessible.authorized_action?(actor: nil, action: EXPORT, recording: :recording)
  end

  def test_audience_options_include_i18n_labels
    configure_kit(allowed: %i[public signed_in granted], default: :granted, granted_roles: %i[view])

    options = RecordingStudioAccessible.audience_options_for(recording: :recording, action: KIT)

    selected = options.map { |option| option[:audience] }
    assert_equal %i[public signed_in granted], selected
    assert_equal "Anyone", options.first.fetch(:label)
    assert_equal "Signed in", options[1].fetch(:label)
    assert_equal "People with access", options.last.fetch(:label)
  end

  def test_constraint_intersects_host_allowed
    configure_kit(allowed: %i[public signed_in granted], default: :public, granted_roles: %i[view])
    constraint = constraint_recording(allowed_audiences: %w[signed_in granted])

    RecordingStudio.stub(:root_recording_or_self, :root) do
      RecordingStudioAccessible::AudienceQuery.stub(:constraint_recording_for, constraint) do
        RecordingStudioAccessible::AudienceQuery.stub(:rule_recording_for, nil) do
          allowed = RecordingStudioAccessible::AudienceResolver.allowed_audiences_for(
            recording: :recording,
            action: KIT
          )
          assert_equal %i[signed_in granted], allowed
          assert_equal :granted, RecordingStudioAccessible.effective_audience(recording: :recording, action: KIT)
        end
      end
    end
  end

  def test_authorized_action_never_reads_another_action
    configure_kit(allowed: %i[public granted], default: :public, granted_roles: %i[view])
    RecordingStudioAccessible.configuration.action_audiences[EXPORT] = {
      allowed: %i[granted],
      default: :granted,
      granted_roles: %i[admin]
    }

    RecordingStudioAccessible.stub(:authorized_for_any_role?, lambda { |**kwargs|
      raise "crossed actions" if kwargs[:roles] == ["admin"]

      false
    }) do
      assert RecordingStudioAccessible.authorized_action?(actor: nil, action: KIT, recording: :recording)
    end
  end

  def test_domain_conditions_are_not_applied_by_accessible
    configure_kit(allowed: %i[public granted], default: :public, granted_roles: %i[view])
    recording = Object.new
    def recording.currently_published? = false

    assert RecordingStudioAccessible.authorized_action?(actor: nil, action: KIT, recording: recording)
  end

  def test_string_action_names_fail_closed_for_audience_config
    configure_kit

    refute RecordingStudioAccessible.authorized_action?(actor: :actor, action: "presskits.kit_download",
                                                        recording: :recording)
    assert_equal :denied, RecordingStudioAccessible.effective_audience(
      recording: :recording,
      action: "presskits.kit_download"
    )
  end

  private

  def configure_kit(allowed: %i[public signed_in granted], default: :granted, granted_roles: %i[download edit admin],
                    granted_override: false, manage_role: :admin)
    RecordingStudioAccessible.configuration.action_audiences[KIT] = {
      allowed: allowed,
      default: default,
      granted_roles: granted_roles,
      granted_override: granted_override,
      manage_role: manage_role
    }
  end

  def rule_recording(audience:)
    recordable = Struct.new(:audience).new(audience.to_s)
    Struct.new(:recordable).new(recordable)
  end

  def constraint_recording(allowed_audiences:)
    recordable = Struct.new(:allowed_audiences).new(allowed_audiences)
    Struct.new(:recordable).new(recordable)
  end
end
