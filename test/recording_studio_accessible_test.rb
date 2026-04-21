# frozen_string_literal: true

require "test_helper"

class RecordingStudioAccessibleTest < Minitest::Test
  def test_version_exists
    refute_nil RecordingStudioAccessible::VERSION
  end

  def test_engine_exists
    assert_kind_of Class, RecordingStudioAccessible::Engine
  end

  def test_compatibility_module_reports_known_mode
    assert_includes %i[addon core], RecordingStudioAccessible::Compatibility.integration_mode
  end

  def test_readme_uses_product_name
    readme = File.read(File.expand_path("../README.md", __dir__))

    assert_includes readme, "Recording Studio Accessible"
    assert_includes readme, "recording_studio_accessible"
  end
end
