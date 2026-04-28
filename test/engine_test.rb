# frozen_string_literal: true

require "test_helper"
require "active_record"

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

  def test_load_missing_constants_initializer_loads_extracted_models_against_top_level_application_record
    return if RecordingStudio.const_defined?(:Access, false)

    application_record = Class.new(::ActiveRecord::Base) do
      self.abstract_class = true
    end

    Object.const_set(:ApplicationRecord, application_record)

    find_initializer("recording_studio_accessible.load_missing_constants").block.call

    assert_equal application_record, RecordingStudio::Access.superclass
    assert_equal application_record, RecordingStudio::AccessBoundary.superclass
  ensure
    RecordingStudio.send(:remove_const, :AccessBoundary) if RecordingStudio.const_defined?(:AccessBoundary, false)
    RecordingStudio.send(:remove_const, :Access) if RecordingStudio.const_defined?(:Access, false)
    Object.send(:remove_const, :ApplicationRecord) if Object.const_defined?(:ApplicationRecord,
                                                                            false) && Object.const_get(:ApplicationRecord) == application_record
  end

  private

  def find_initializer(name)
    RecordingStudioAccessible::Engine.initializers.find { |initializer| initializer.name == name }
  end
end
