# frozen_string_literal: true

require "test_helper"

class RecordingStudioAccessibleTest < Minitest::Test
  def test_version_matches_the_current_release
    assert_equal "0.45.1", RecordingStudioAccessible::VERSION
  end

  def test_recording_studio_version_is_at_least_7_0
    assert_operator Gem::Version.new(RecordingStudio::VERSION), :>=, Gem::Version.new("7.0.0")
    assert_operator Gem::Version.new(RecordingStudio::VERSION), :<, Gem::Version.new("8.0.0")
    assert_operator Gem.loaded_specs.fetch("recording_studio").version, :>=, Gem::Version.new("7.0.0")
    assert_operator Gem::Version.new(RecordingStudioTrashable::VERSION), :>=, Gem::Version.new("0.17.0")
    assert_operator Gem::Version.new(RecordingStudioTrashable::VERSION), :<, Gem::Version.new("2.0.0")

    gemspec = File.read(File.expand_path("../recording_studio_accessible.gemspec", __dir__))
    assert_includes gemspec, '"recording_studio", ">= 7.0", "< 8.0"'
    assert_includes gemspec, '"recording_studio_trashable", ">= 0.17.0", "< 2.0"'
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
