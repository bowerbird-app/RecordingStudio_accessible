# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"
require "generators/recording_studio_accessible/install/install_generator"

class InstallGeneratorTest < Minitest::Test
  def with_temp_app
    Dir.mktmpdir do |dir|
      yield dir
    end
  end

  def build_generator(destination_root, options = {})
    RecordingStudioAccessible::Generators::InstallGenerator.new([], options, destination_root: destination_root)
  end

  def test_mount_engine_is_opt_in
    generator = build_generator("/tmp")
    routes = []

    generator.stub(:route, ->(value) { routes << value }) do
      generator.mount_engine
    end

    assert_empty routes
  end

  def test_mount_engine_uses_configured_mount_path_when_enabled
    generator = build_generator("/tmp", mount: true, mount_path: "/addons/access")
    routes = []

    generator.stub(:route, ->(value) { routes << value }) do
      generator.mount_engine
    end

    assert_equal ['mount RecordingStudioAccessible::Engine, at: "/addons/access"'], routes
  end

  def test_add_yaml_config_copies_template_when_accepted
    with_temp_app do |dir|
      generator = build_generator(dir)

      generator.stub(:yes?, true) do
        generator.add_yaml_config
      end

      assert File.exist?(File.join(dir, "config/recording_studio_accessible.yml"))
    end
  end
end
