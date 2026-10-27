# frozen_string_literal: true

require "test_helper"

class CompanionPinTest < Minitest::Test
  ROOT_PINS = {
    "recording_studio" => "6.1.0",
    "flat_pack" => "0.1.320",
    "recording_studio_trashable" => "0.12.0",
    "recording_studio_attachable" => "0.22.0",
    "recording_studio_user" => "0.25.2",
    "recording_studio_metrics" => "0.6.1",
    "recording_studio_admin" => "2.5.1"
  }.freeze

  DUMMY_ONLY_PINS = {
    "recording_studio_root_switchable" => "0.11.0",
    "recording_studio_notifications" => "0.13.1"
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
