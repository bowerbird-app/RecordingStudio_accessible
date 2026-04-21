# frozen_string_literal: true

require "test_helper"

class CompatibilityTest < Minitest::Test
  def test_integration_mode_is_core_when_core_access_present
    RecordingStudioAccessible::Compatibility.stub(:missing_constant_paths, []) do
      assert_equal :core, RecordingStudioAccessible::Compatibility.integration_mode
    end
  end

  def test_integration_mode_is_addon_when_core_access_missing
    RecordingStudioAccessible::Compatibility.stub(:missing_constant_paths, ["recording_studio_accessible/extracted/recording_studio/access"]) do
      assert_equal :addon, RecordingStudioAccessible::Compatibility.integration_mode
    end
  end

  def test_missing_constant_paths_load_in_dependency_order
    RecordingStudioAccessible::Compatibility.singleton_class.class_eval do
      define_method(:constant_defined_path?) { |_path| false }
    end

    expected = [
      "recording_studio_accessible/extracted/recording_studio/access",
      "recording_studio_accessible/extracted/recording_studio/access_boundary",
      "recording_studio_accessible/extracted/recording_studio/services/access_check_class_methods",
      "recording_studio_accessible/extracted/recording_studio/services/access_check"
    ]

    assert_equal expected, RecordingStudioAccessible::Compatibility.missing_constant_paths
  ensure
    RecordingStudioAccessible::Compatibility.singleton_class.send(:remove_method, :constant_defined_path?)
  end

  def test_ensure_recordable_types_registered
    registered = []

    RecordingStudioAccessible::Compatibility.singleton_class.class_eval do
      define_method(:constant_defined_path?) { |_path| true }
    end

    RecordingStudio.stub(:register_recordable_type, ->(name) { registered << name }) do
      RecordingStudioAccessible::Compatibility.ensure_recordable_types_registered!
    end

    assert_includes registered, "RecordingStudio::Access"
    assert_includes registered, "RecordingStudio::AccessBoundary"
  ensure
    RecordingStudioAccessible::Compatibility.singleton_class.send(:remove_method, :constant_defined_path?)
  end
end
