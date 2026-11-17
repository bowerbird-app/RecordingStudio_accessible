# frozen_string_literal: true

require "test_helper"

class CompanionPinTest < Minitest::Test
  ROOT_PINS = {
    "recording_studio" => "7.7.0",
    "flat_pack" => "0.1.377",
    "recording_studio_trashable" => "1.0.1",
    "recording_studio_attachable" => "0.31.0",
    "recording_studio_user" => "0.32.0",
    "recording_studio_metrics" => "0.9.0",
    "recording_studio_cache" => "0.7.0",
    "recording_studio_admin" => "2.18.0",
    "recording_studio_api" => "1.2.1",
    "recording_studio_icons" => "0.4.0",
    "recording_studio_logs" => "0.8.0",
    "recording_studio_moveable" => "6.0.0"
  }.freeze

  DUMMY_ONLY_PINS = {
    "recording_studio_root_switchable" => "0.16.0",
    "recording_studio_notifications" => "0.19.1",
    "recording_studio_internationalization" => "0.3.0"
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
