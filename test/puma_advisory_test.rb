# frozen_string_literal: true

require "test_helper"

class PumaAdvisoryTest < Minitest::Test
  def test_lockfiles_pin_a_patched_puma
    [lockfile, dummy_lockfile].each do |path|
      version = File.read(path)[/puma \(([^)]+)\)/, 1]

      assert version, "puma is missing from #{path}"
      assert patched?(version), "#{path} pins puma #{version}, which is not a patched release"
    end
  end

  private

  def patched?(version)
    current = Gem::Version.new(version)
    return current >= Gem::Version.new("8.0.2") if current >= Gem::Version.new("8.0.0")

    current >= Gem::Version.new("7.2.1") && current < Gem::Version.new("8.0.0")
  end

  def lockfile
    File.expand_path("../Gemfile.lock", __dir__)
  end

  def dummy_lockfile
    File.expand_path("../test/dummy/Gemfile.lock", __dir__)
  end
end
