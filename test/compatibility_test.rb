# frozen_string_literal: true

require "test_helper"

class CompatibilityTest < Minitest::Test
  def test_integration_mode_is_core_when_core_access_present
    RecordingStudioAccessible::Compatibility.stub(:missing_constant_paths, []) do
      assert_equal :core, RecordingStudioAccessible::Compatibility.integration_mode
    end
  end

  def test_integration_mode_is_addon_when_core_access_missing
    RecordingStudioAccessible::Compatibility.stub(:missing_constant_paths,
                                                  ["recording_studio_accessible/extracted/recording_studio/access"]) do
      assert_equal :addon, RecordingStudioAccessible::Compatibility.integration_mode
    end
  end

  def test_missing_constant_paths_load_in_dependency_order
    singleton = RecordingStudioAccessible::Compatibility.singleton_class
    original_method = singleton.instance_method(:constant_defined_path?)
    singleton.send(:define_method, :constant_defined_path?) { |_path| false }

    expected = [
      "recording_studio_accessible/extracted/recording_studio/access"
    ]

    assert_equal expected, RecordingStudioAccessible::Compatibility.missing_constant_paths
  ensure
    singleton.send(:define_method, :constant_defined_path?, original_method)
  end

  def test_ensure_recordable_types_registered
    registered = []

    singleton = RecordingStudioAccessible::Compatibility.singleton_class
    original_method = singleton.instance_method(:constant_defined_path?)
    singleton.send(:define_method, :constant_defined_path?) { |_path| true }

    RecordingStudio.stub(:register_recordable_type, ->(name) { registered << name }) do
      RecordingStudioAccessible::Compatibility.ensure_recordable_types_registered!
    end

    assert_includes registered, "RecordingStudio::Access"
  ensure
    singleton.send(:define_method, :constant_defined_path?, original_method)
  end

  def test_ensure_creation_guards_includes_access_guard_for_core_access
    access_class = Class.new do
      def self.before_create(callback)
        callbacks << callback
      end

      def self.callbacks
        @callbacks ||= []
      end
    end

    recording_class = Class.new do
      def self.before_create(callback)
        callbacks << callback
      end

      def self.callbacks
        @callbacks ||= []
      end
    end

    RecordingStudio.stub(:const_defined?, lambda { |name, inherit = true|
      %w[Access Recording].include?(name.to_s) || Object.const_defined?(name, inherit)
    }) do
      RecordingStudio.stub(:const_get, lambda { |name, inherit = true|
        case name.to_s
        when "Access" then access_class
        when "Recording" then recording_class
        else Object.const_get(name, inherit)
        end
      }) do
        RecordingStudioAccessible::Compatibility.ensure_creation_guards!
      end
    end

    assert_includes access_class.included_modules, RecordingStudioAccessible::AccessCreationGuard
    assert_includes access_class.callbacks, :prevent_unsupported_direct_creation
    assert_includes recording_class.included_modules, RecordingStudioAccessible::AccessRecordingCreationGuard
    assert_includes recording_class.callbacks, :prevent_unsupported_access_recording_creation
  end
end
