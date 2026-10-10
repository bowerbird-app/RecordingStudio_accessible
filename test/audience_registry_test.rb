# frozen_string_literal: true

require "test_helper"

class AudienceRegistryTest < Minitest::Test
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

  def test_built_in_audiences_are_registered
    %i[public signed_in granted].each do |name|
      assert RecordingStudioAccessible.registered_audience?(name), "#{name} should be registered"
    end

    assert_equal %i[granted public signed_in], RecordingStudioAccessible.registered_audiences.keys.sort
  end

  def test_register_audience_stores_label_key_and_predicate
    RecordingStudioAccessible.register_audience(
      :"presskits.verified_journalist",
      label_key: "recording_studio_presskits.audiences.verified_journalist"
    ) { |actor:| actor == :journalist }

    metadata = RecordingStudioAccessible.audience_registration_for(:"presskits.verified_journalist")

    assert_equal :"presskits.verified_journalist", metadata.fetch(:name)
    assert_equal "recording_studio_presskits.audiences.verified_journalist", metadata.fetch(:label_key)
    assert RecordingStudioAccessible.audience_registry.evaluate(
      :"presskits.verified_journalist",
      actor: :journalist,
      recording: :recording,
      context: {}
    )
    refute RecordingStudioAccessible.audience_registry.evaluate(
      :"presskits.verified_journalist",
      actor: :reader,
      recording: :recording,
      context: {}
    )
  end

  def test_register_audience_requires_symbol_name_and_block
    assert_raises(ArgumentError) { RecordingStudioAccessible.register_audience(nil) { true } }
    assert_raises(ArgumentError) { RecordingStudioAccessible.register_audience("") { true } }
    assert_raises(ArgumentError) { RecordingStudioAccessible.register_audience("public") { true } }
    assert_raises(ArgumentError) { RecordingStudioAccessible.register_audience(:" ") { true } }
    assert_raises(ArgumentError) { RecordingStudioAccessible.register_audience(:custom) }
  end

  def test_unknown_audience_evaluation_fails_closed
    refute RecordingStudioAccessible.audience_registry.evaluate(
      :missing,
      actor: :actor,
      recording: :recording
    )
    refute RecordingStudioAccessible.audience_registry.evaluate(
      "public",
      actor: :actor,
      recording: :recording
    )
  end

  def test_predicate_exception_fails_closed
    RecordingStudioAccessible.register_audience(:boom) { raise "nope" }

    refute RecordingStudioAccessible.audience_registry.evaluate(
      :boom,
      actor: :actor,
      recording: :recording
    )
  end

  def test_public_allows_nil_actor
    assert RecordingStudioAccessible.audience_registry.evaluate(
      :public,
      actor: nil,
      recording: :recording
    )
  end

  def test_signed_in_requires_actor
    refute RecordingStudioAccessible.audience_registry.evaluate(
      :signed_in,
      actor: nil,
      recording: :recording
    )
    assert RecordingStudioAccessible.audience_registry.evaluate(
      :signed_in,
      actor: :actor,
      recording: :recording
    )
  end

  def test_non_hash_context_fails_closed
    RecordingStudioAccessible.register_audience(:custom) { true }

    refute RecordingStudioAccessible.audience_registry.evaluate(
      :custom,
      actor: :actor,
      recording: :recording,
      context: "invalid"
    )
  end

  def test_clear_restores_built_ins
    RecordingStudioAccessible.register_audience(:custom) { true }
    RecordingStudioAccessible.audience_registry.clear!

    refute RecordingStudioAccessible.registered_audience?(:custom)
    assert RecordingStudioAccessible.registered_audience?(:public)
  end

  def test_registration_metadata_is_isolated_from_mutation
    RecordingStudioAccessible.register_audience(:custom, label_key: +"my.key") { true }

    metadata = RecordingStudioAccessible.audience_registration_for(:custom)
    metadata[:label_key] = "changed"
    metadata[:name] = :other

    stored = RecordingStudioAccessible.audience_registration_for(:custom)
    assert_equal :custom, stored.fetch(:name)
    assert_equal "my.key", stored.fetch(:label_key)
  end

  def test_configuration_delegates_register_audience
    RecordingStudioAccessible.configure do |config|
      config.register_audience(:custom, label_key: "custom.label") { true }
    end

    assert RecordingStudioAccessible.configuration.registered_audiences.key?(:custom)
  end
end
