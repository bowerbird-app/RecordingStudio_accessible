# frozen_string_literal: true

require "test_helper"

class RecordingStudioAccessibleTest < Minitest::Test
  def test_version_matches_the_current_release
    assert_equal "0.13.0", RecordingStudioAccessible::VERSION
  end

  def test_recording_studio_version_is_4_4
    assert_equal "4.4.0", RecordingStudio::VERSION
    assert_equal Gem::Version.new("4.4.0"), Gem.loaded_specs.fetch("recording_studio").version
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
    assert_includes readme, "## Internationalization"
    assert_includes readme, "recording_studio.accessible"
  end

  def test_dummy_layouts_carry_locale_and_language_selector
    sidebar = File.read(File.expand_path("dummy/app/views/layouts/flat_pack_sidebar.html.erb", __dir__))
    application = File.read(File.expand_path("dummy/app/views/layouts/application.html.erb", __dir__))
    top_nav = File.read(File.expand_path("dummy/app/views/layouts/flat_pack/_top_nav.html.erb", __dir__))
    gemspec = File.read(File.expand_path("../recording_studio_accessible.gemspec", __dir__))
    dummy_gemfile = File.read(File.expand_path("dummy/Gemfile", __dir__))

    assert_includes sidebar, "dummy_document_attributes"
    assert_includes application, "dummy_document_attributes"
    assert_includes top_nav, "dummy_language_selector"
    refute_includes gemspec, "recording_studio_internationalization"
    assert_includes dummy_gemfile, "recording_studio_internationalization"
  end
end
