# frozen_string_literal: true

require "test_helper"

class ActionRegistryTest < Minitest::Test
  Actor = Struct.new(:subscribed)

  def setup
    @original_action_registry = RecordingStudioAccessible.instance_variable_get(:@action_registry)
    @original_check_registry = RecordingStudioAccessible.instance_variable_get(:@check_registry)
    RecordingStudioAccessible.instance_variable_set(:@action_registry, RecordingStudioAccessible::ActionRegistry.new)
    RecordingStudioAccessible.instance_variable_set(:@check_registry, RecordingStudioAccessible::CheckRegistry.new)
  end

  def teardown
    RecordingStudioAccessible.instance_variable_set(:@action_registry, @original_action_registry)
    RecordingStudioAccessible.instance_variable_set(:@check_registry, @original_check_registry)
  end

  def test_registers_action_metadata
    RecordingStudioAccessible.register_action(
      :"recording_studio_messages.create_group",
      label: "Create message group",
      description: "Allows an actor to start a new message group.",
      source: "recording_studio_messages",
      recording_required: true
    )

    metadata = RecordingStudioAccessible.action_registration_for(:"recording_studio_messages.create_group")

    assert RecordingStudioAccessible.registered_action?(:"recording_studio_messages.create_group")
    assert_equal :"recording_studio_messages.create_group", metadata.fetch(:name)
    assert_equal "Create message group", metadata.fetch(:label)
    assert_equal "Allows an actor to start a new message group.", metadata.fetch(:description)
    assert_equal "recording_studio_messages", metadata.fetch(:source)
    assert_equal true, metadata.fetch(:recording_required)
  end

  def test_recording_required_defaults_to_false
    RecordingStudioAccessible.register_action(:subscribed, label: "Subscribed", source: "application")

    assert_equal false, RecordingStudioAccessible.action_registration_for(:subscribed).fetch(:recording_required)
  end

  def test_duplicate_same_source_registration_is_idempotent
    first = RecordingStudioAccessible.register_action(:subscribed, label: "Subscribed", source: "application")
    second = RecordingStudioAccessible.register_action(:subscribed, label: "Subscribed", source: "application")

    assert_equal first, second
    assert_equal({ subscribed: first }, RecordingStudioAccessible.registered_actions)
  end

  def test_conflicting_duplicate_registration_uses_latest_metadata_without_weakening_recording_requirement
    RecordingStudioAccessible.register_action(
      :publish,
      label: "Publish",
      source: "recording_studio_publishable",
      recording_required: true
    )
    RecordingStudioAccessible.register_action(:publish, label: "Site publish", source: "application")

    metadata = RecordingStudioAccessible.action_registration_for(:publish)

    assert_equal "Site publish", metadata.fetch(:label)
    assert_equal "application", metadata.fetch(:source)
    assert_equal true, metadata.fetch(:recording_required)
  end

  def test_registration_metadata_is_isolated_from_mutation
    label = +"Subscribed"
    RecordingStudioAccessible.register_action(:subscribed, label: label, source: "application")

    label.replace("Changed")
    metadata = RecordingStudioAccessible.action_registration_for(:subscribed)

    assert_equal "Subscribed", metadata.fetch(:label)
    assert_raises(FrozenError) { metadata.fetch(:label).replace("Changed again") }
  end

  def test_nested_registration_metadata_is_isolated_from_mutation
    label = { text: +"Subscribed", tags: [+"global"] }
    RecordingStudioAccessible.register_action(:subscribed, label: label)

    label[:text].replace("Changed")
    label[:tags].first.replace("changed")

    metadata = RecordingStudioAccessible.action_registration_for(:subscribed)
    assert_equal({ text: "Subscribed", tags: ["global"] }, metadata.fetch(:label))
    assert metadata.fetch(:label).frozen?
    assert metadata.fetch(:label).fetch(:text).frozen?
    assert metadata.fetch(:label).fetch(:tags).frozen?
    assert metadata.fetch(:label).fetch(:tags).first.frozen?
  end

  def test_returned_action_registration_is_isolated_from_mutation
    RecordingStudioAccessible.register_action(:subscribed, label: "Subscribed", source: "application")

    metadata = RecordingStudioAccessible.action_registration_for(:subscribed)
    metadata[:label] = "Changed"
    metadata[:recording_required] = true

    stored_metadata = RecordingStudioAccessible.action_registration_for(:subscribed)
    assert_equal "Subscribed", stored_metadata.fetch(:label)
    assert_equal false, stored_metadata.fetch(:recording_required)
  end

  def test_returned_nested_action_registration_metadata_is_read_only
    RecordingStudioAccessible.register_action(:subscribed, label: { text: "Subscribed", tags: ["global"] })

    metadata = RecordingStudioAccessible.action_registration_for(:subscribed)

    assert_raises(FrozenError) { metadata.fetch(:label)[:text] = "Changed" }
    assert_raises(FrozenError) { metadata.fetch(:label).fetch(:tags) << "changed" }
    assert_equal({ text: "Subscribed", tags: ["global"] },
                 RecordingStudioAccessible.action_registration_for(:subscribed).fetch(:label))
  end

  def test_registered_actions_snapshot_is_isolated_from_mutation
    RecordingStudioAccessible.register_action(:subscribed, label: "Subscribed", source: "application")

    actions = RecordingStudioAccessible.registered_actions
    actions[:subscribed][:label] = "Changed"
    actions[:extra] = { name: :extra }

    assert_equal [:subscribed], RecordingStudioAccessible.registered_actions.keys
    assert_equal "Subscribed", RecordingStudioAccessible.action_registration_for(:subscribed).fetch(:label)
  end

  def test_register_action_requires_symbol_name
    assert_raises(ArgumentError) { RecordingStudioAccessible.register_action(nil) }
    assert_raises(ArgumentError) { RecordingStudioAccessible.register_action("") }
    assert_raises(ArgumentError) { RecordingStudioAccessible.register_action("subscribed") }
    assert_raises(ArgumentError) { RecordingStudioAccessible.register_action(:" ") }
  end

  def test_define_action_lists_policy_and_allows_true_result
    RecordingStudioAccessible.define_action(:subscribed) do |actor:, action:, recording:, context:, controller:|
      [actor, action, recording, context, controller] == [:actor, :subscribed, nil, {}, nil]
    end

    assert RecordingStudioAccessible.action_defined?(:subscribed)
    assert RecordingStudioAccessible.action_policy_defined?(:subscribed)
    assert_equal [:subscribed], RecordingStudioAccessible.defined_actions
    assert RecordingStudioAccessible.authorized_action?(actor: :actor, action: :subscribed)
  end

  def test_define_action_requires_symbol_name_and_block
    assert_raises(ArgumentError) { RecordingStudioAccessible.define_action(nil) { true } }
    assert_raises(ArgumentError) { RecordingStudioAccessible.define_action("") { true } }
    assert_raises(ArgumentError) { RecordingStudioAccessible.define_action("subscribed") { true } }
    assert_raises(ArgumentError) { RecordingStudioAccessible.define_action(:" ") { true } }
    assert_raises(ArgumentError) { RecordingStudioAccessible.define_action(:subscribed) }
  end

  def test_redefining_action_uses_latest_policy
    RecordingStudioAccessible.define_action(:zebra) { false }
    RecordingStudioAccessible.define_action(:alpha) { true }
    RecordingStudioAccessible.define_action(:zebra) { true }

    assert_equal %i[alpha zebra], RecordingStudioAccessible.defined_actions
    assert RecordingStudioAccessible.authorized_action?(actor: :actor, action: :zebra)
  end

  def test_action_policy_introspection_is_read_only
    RecordingStudioAccessible.define_action(:subscribed) { true }

    policies = RecordingStudioAccessible.action_policies

    assert policies.frozen?
    assert policies.fetch(:subscribed).frozen?
    assert_raises(FrozenError) { policies[:other] = policies.fetch(:subscribed) }
  end

  def test_authorized_action_returns_boolean_false_for_falsey_policy
    RecordingStudioAccessible.define_action(:subscribed) { nil }

    refute RecordingStudioAccessible.authorized_action?(actor: :actor, action: :subscribed)
  end

  def test_missing_policy_and_blank_action_fail_closed
    refute RecordingStudioAccessible.authorized_action?(actor: :actor, action: :missing)
    refute RecordingStudioAccessible.authorized_action?(actor: :actor, action: nil)
    refute RecordingStudioAccessible.authorized_action?(actor: :actor, action: "")
  end

  def test_policy_exception_fails_closed
    RecordingStudioAccessible.define_action(:dangerous) { raise "boom" }

    refute RecordingStudioAccessible.authorized_action?(actor: :actor, action: :dangerous)
  end

  def test_action_policy_can_accept_only_needed_keywords
    policy = ->(actor:) { actor == :actor }
    RecordingStudioAccessible.define_action(:subscribed, &policy)

    assert RecordingStudioAccessible.authorized_action?(
      actor: :actor,
      action: :subscribed,
      recording: :ignored,
      context: { ignored: true },
      controller: :ignored
    )
  end

  def test_recording_required_registration_denies_nil_recording_before_policy
    called = false
    RecordingStudioAccessible.register_action(:export, source: "recording_studio_exportable", recording_required: true)
    RecordingStudioAccessible.define_action(:export) do
      called = true
      true
    end

    refute RecordingStudioAccessible.authorized_action?(actor: :actor, action: :export)
    refute called
  end

  def test_recording_required_registration_calls_policy_when_recording_is_present
    RecordingStudioAccessible.register_action(:export, source: "recording_studio_exportable", recording_required: true)
    RecordingStudioAccessible.define_action(:export) { |recording:, **| recording == :recording }

    assert RecordingStudioAccessible.authorized_action?(actor: :actor, action: :export, recording: :recording)
  end

  def test_unregistered_action_with_defined_policy_is_authorized_by_policy
    RecordingStudioAccessible.define_action(:subscribed) { true }

    assert RecordingStudioAccessible.authorized_action?(actor: :actor, action: :subscribed)
  end

  def test_context_and_controller_are_passed_through_unchanged
    context = { messages_key: :site_messages }
    controller = Object.new
    received = nil
    RecordingStudioAccessible.define_action(:create_group) do |context:, controller:, **|
      received = [context, controller]
    end

    RecordingStudioAccessible.authorized_action?(
      actor: :actor,
      action: :create_group,
      context: context,
      controller: controller
    )

    assert_same context, received.first
    assert_same controller, received.last
  end

  def test_nil_context_is_normalized_to_hash
    RecordingStudioAccessible.define_action(:subscribed) { |context:, **| context == {} }

    assert RecordingStudioAccessible.authorized_action?(actor: :actor, action: :subscribed, context: nil)
  end

  def test_non_hash_context_fails_closed
    RecordingStudioAccessible.define_action(:subscribed) { true }

    refute RecordingStudioAccessible.authorized_action?(actor: :actor, action: :subscribed, context: "invalid")
  end

  def test_checks_can_be_defined_called_and_composed_in_action_policies
    actor = Actor.new(true)
    RecordingStudioAccessible.define_check(:subscribed) do |actor:, recording:, context:, controller:|
      actor.subscribed && recording == :recording && context[:feature] == :messages && controller == :controller
    end
    RecordingStudioAccessible.define_action(:create_group) do |actor:, recording:, context:, controller:, **|
      RecordingStudioAccessible.check(
        :subscribed,
        actor: actor,
        recording: recording,
        context: context,
        controller: controller
      )
    end

    assert RecordingStudioAccessible.check_defined?(:subscribed)
    assert_equal [:subscribed], RecordingStudioAccessible.defined_checks
    assert RecordingStudioAccessible.authorized_action?(
      actor: actor,
      action: :create_group,
      recording: :recording,
      context: { feature: :messages },
      controller: :controller
    )
  end

  def test_missing_and_raising_checks_fail_closed
    refute RecordingStudioAccessible.check(:missing, actor: :actor)

    RecordingStudioAccessible.define_check(:raising) { raise "boom" }

    refute RecordingStudioAccessible.check(:raising, actor: :actor)
  end

  def test_check_nil_context_is_normalized_to_hash
    RecordingStudioAccessible.define_check(:signed_in) { |context:, **| context == {} }

    assert RecordingStudioAccessible.check(:signed_in, actor: :actor, context: nil)
  end

  def test_check_non_hash_context_fails_closed_without_calling_predicate
    called = false
    RecordingStudioAccessible.define_check(:signed_in) do
      called = true
      true
    end

    refute RecordingStudioAccessible.check(:signed_in, actor: :actor, context: "invalid")
    refute called
  end

  def test_define_check_requires_symbol_name_and_block
    assert_raises(ArgumentError) { RecordingStudioAccessible.define_check(nil) { true } }
    assert_raises(ArgumentError) { RecordingStudioAccessible.define_check("") { true } }
    assert_raises(ArgumentError) { RecordingStudioAccessible.define_check("signed_in") { true } }
    assert_raises(ArgumentError) { RecordingStudioAccessible.define_check(:" ") { true } }
    assert_raises(ArgumentError) { RecordingStudioAccessible.define_check(:signed_in) }
  end

  def test_redefining_check_uses_latest_predicate
    RecordingStudioAccessible.define_check(:zebra) { false }
    RecordingStudioAccessible.define_check(:alpha) { true }
    RecordingStudioAccessible.define_check(:zebra) { true }

    assert_equal %i[alpha zebra], RecordingStudioAccessible.defined_checks
    assert RecordingStudioAccessible.check(:zebra, actor: :actor)
  end

  def test_check_introspection_is_read_only
    RecordingStudioAccessible.define_check(:signed_in) { true }

    checks = RecordingStudioAccessible.check_registry.checks

    assert checks.frozen?
    assert checks.fetch(:signed_in).frozen?
    assert_raises(FrozenError) { checks[:other] = checks.fetch(:signed_in) }
  end

  def test_check_can_accept_only_needed_keywords
    RecordingStudioAccessible.define_check(:signed_in) { |actor:| actor == :actor }

    assert RecordingStudioAccessible.check(
      :signed_in,
      actor: :actor,
      recording: :ignored,
      context: { ignored: true },
      controller: :ignored
    )
  end

  def test_string_action_and_check_names_fail_closed
    RecordingStudioAccessible.define_action(:subscribed) { true }
    RecordingStudioAccessible.define_check(:signed_in) { true }

    refute RecordingStudioAccessible.authorized_action?(actor: :actor, action: "subscribed")
    refute RecordingStudioAccessible.check("signed_in", actor: :actor)
    refute RecordingStudioAccessible.registered_action?("subscribed")
    refute RecordingStudioAccessible.action_defined?("subscribed")
    refute RecordingStudioAccessible.check_defined?("signed_in")
  end

  def test_configuration_delegates_to_action_and_check_apis
    RecordingStudioAccessible.configure do |config|
      config.register_action(:subscribed, source: "application")
      config.define_check(:signed_in) { |actor:, **| actor == :actor }
      config.define_action(:subscribed) do |actor:, **|
        config.check(:signed_in, actor: actor)
      end
    end

    assert RecordingStudioAccessible.configuration.registered_actions.key?(:subscribed)
    assert_equal [:subscribed], RecordingStudioAccessible.configuration.defined_actions
    assert_equal [:signed_in], RecordingStudioAccessible.configuration.defined_checks
    assert RecordingStudioAccessible.configuration.authorized_action?(actor: :actor, action: :subscribed)
  end

  def test_action_authorization_does_not_call_ordinary_access_implicitly
    RecordingStudioAccessible.register_action(:export, source: "recording_studio_exportable", recording_required: true)
    RecordingStudioAccessible.define_action(:export) { true }

    RecordingStudioAccessible.stub(:authorized?, ->(**) { raise "ordinary access should not be called" }) do
      assert RecordingStudioAccessible.authorized_action?(actor: :actor, action: :export, recording: :recording)
    end
  end

  def test_ordinary_access_does_not_grant_action_permission_implicitly
    RecordingStudioAccessible.register_action(:export, source: "recording_studio_exportable", recording_required: true)

    RecordingStudioAccessible.stub(:authorized?, true) do
      refute RecordingStudioAccessible.authorized_action?(actor: :actor, action: :export, recording: :recording)
    end
  end
end
