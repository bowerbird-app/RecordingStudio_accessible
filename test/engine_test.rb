# frozen_string_literal: true

require "test_helper"

class EngineTest < Minitest::Test
  def setup
    @original_configuration = RecordingStudioAccessible.instance_variable_get(:@configuration)
    RecordingStudioAccessible.instance_variable_set(:@configuration, RecordingStudioAccessible::Configuration.new)
  end

  def teardown
    RecordingStudioAccessible.configuration.hooks.clear!
    RecordingStudioAccessible.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_before_and_after_initialize_initializers_run_hooks
    before_called = false
    after_called = false

    RecordingStudioAccessible.configuration.hooks.before_initialize { before_called = true }
    RecordingStudioAccessible.configuration.hooks.after_initialize { after_called = true }

    find_initializer("recording_studio_accessible.before_initialize").block.call
    find_initializer("recording_studio_accessible.after_initialize").block.call

    assert before_called
    assert after_called
  end

  def test_load_config_merges_yaml_and_config_x
    xcfg = Struct.new(:recording_studio_accessible).new({ warn_on_core_conflict: false })
    app_config = Struct.new(:x).new(xcfg)
    app = Struct.new(:config) do
      def config_for(_name)
        { warn_on_core_conflict: true }
      end
    end.new(app_config)

    find_initializer("recording_studio_accessible.load_config").block.call(app)

    assert_equal false, RecordingStudioAccessible.configuration.warn_on_core_conflict
  end

  def test_register_access_types_initializer_calls_compatibility_helpers
    warned = false
    registered = false

    RecordingStudioAccessible::Compatibility.stub(:warn_if_core_access_present!, -> { warned = true }) do
      RecordingStudioAccessible::Compatibility.stub(:ensure_recordable_types_registered!, -> { registered = true }) do
        find_initializer("recording_studio_accessible.register_access_types").block.call
      end
    end

    assert warned
    assert registered
  end

  private

  def find_initializer(name)
    RecordingStudioAccessible::Engine.initializers.find { |initializer| initializer.name == name }
  end
end
