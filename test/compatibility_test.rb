# frozen_string_literal: true

require "test_helper"

class CompatibilityTest < Minitest::Test
  def test_integration_mode_is_core_when_core_access_present
    RecordingStudioAccessible::Compatibility.stub(:core_access_present?, true) do
      assert_equal :core, RecordingStudioAccessible::Compatibility.integration_mode
    end
  end

  def test_integration_mode_is_addon_when_core_access_missing
    RecordingStudioAccessible::Compatibility.stub(:core_access_present?, false) do
      assert_equal :addon, RecordingStudioAccessible::Compatibility.integration_mode
    end
  end

  def test_ensure_recordable_types_registered
    registered = []

    RecordingStudio.stub(:register_recordable_type, ->(name) { registered << name }) do
      RecordingStudioAccessible::Compatibility.ensure_recordable_types_registered!
    end

    assert_includes registered, "RecordingStudio::Access"
    assert_includes registered, "RecordingStudio::AccessBoundary"
  end
end
