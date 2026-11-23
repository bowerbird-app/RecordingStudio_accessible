# frozen_string_literal: true

require "test_helper"

class CompanionPinTest < Minitest::Test
  ROOT_PINS = {
    "recording_studio" => "7.8.0",
    "flat_pack" => "0.2.0",
    "recording_studio_trashable" => "1.2.3",
    "recording_studio_attachable" => "0.33.2",
    "recording_studio_user" => "0.38.0",
    "recording_studio_metrics" => "0.9.2",
    "recording_studio_cache" => "0.7.1",
    "recording_studio_admin" => "2.19.1",
    "recording_studio_api" => "1.19.0",
    "recording_studio_icons" => "0.4.2",
    "recording_studio_logs" => "0.8.2",
    "recording_studio_moveable" => "6.0.3"
  }.freeze

  DUMMY_ONLY_PINS = {
    "recording_studio_api" => "1.21.3",
    "recording_studio_mcp" => "0.45.2",
    "recording_studio_oauth" => "0.26.0",
    "recording_studio_site_settings" => "0.6.0",
    "recording_studio_root_switchable" => "0.16.1",
    "recording_studio_notifications" => "0.19.5",
    "recording_studio_internationalization" => "0.3.1"
  }.freeze

  def test_root_lockfile_matches_companion_pins
    assert_pins lockfile, ROOT_PINS
  end

  def test_dummy_lockfile_matches_companion_pins
    assert_pins dummy_lockfile, ROOT_PINS.merge(DUMMY_ONLY_PINS)
  end

  private

  def assert_pins(path, pins)
    contents = File.read(path)

    pins.each do |name, version|
      assert_includes contents, "#{name} (#{version})", "#{path} should pin #{name} #{version}"
    end
  end

  def lockfile
    File.expand_path("../Gemfile.lock", __dir__)
  end

  def dummy_lockfile
    File.expand_path("../test/dummy/Gemfile.lock", __dir__)
  end
end
