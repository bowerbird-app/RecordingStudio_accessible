# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"
require "generators/recording_studio_accessible/access_management/access_management_generator"

class AccessManagementGeneratorTest < Minitest::Test
  def with_temp_app
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config/routes.rb"), "Rails.application.routes.draw do\nend\n")
      yield dir
    end
  end

  def build_generator(destination_root, options = {})
    RecordingStudioAccessible::Generators::AccessManagementGenerator.new([], options, destination_root: destination_root)
  end

  def test_mount_engine_uses_configured_mount_path
    with_temp_app do |dir|
      generator = build_generator(dir, mount_path: "/addons/access")

      generator.mount_engine

      routes = File.read(File.join(dir, "config/routes.rb"))
      assert_includes routes, 'mount RecordingStudioAccessible::Engine, at: "/addons/access"'
    end
  end

  def test_mount_engine_skips_when_mount_already_present
    with_temp_app do |dir|
      File.write(
        File.join(dir, "config/routes.rb"),
        "Rails.application.routes.draw do\n  mount RecordingStudioAccessible::Engine, at: \"/recording_studio_accessible\"\nend\n"
      )

      generator = build_generator(dir)
      original_routes = File.read(File.join(dir, "config/routes.rb"))

      generator.mount_engine

      assert_equal original_routes, File.read(File.join(dir, "config/routes.rb"))
    end
  end

  def test_copy_initializer_creates_initializer_when_missing
    with_temp_app do |dir|
      generator = build_generator(dir)

      generator.copy_initializer

      assert File.exist?(File.join(dir, "config/initializers/recording_studio_accessible.rb"))
    end
  end

  def test_copy_initializer_preserves_existing_initializer
    with_temp_app do |dir|
      initializer = File.join(dir, "config/initializers/recording_studio_accessible.rb")
      FileUtils.mkdir_p(File.dirname(initializer))
      File.write(initializer, "# existing\n")

      generator = build_generator(dir)
      generator.copy_initializer

      assert_equal "# existing\n", File.read(initializer)
    end
  end

  def test_copy_helper_is_opt_in
    with_temp_app do |dir|
      generator = build_generator(dir)

      generator.copy_helper

      refute File.exist?(File.join(dir, "app/helpers/recording_studio_accessible/access_management_helper.rb"))
    end
  end

  def test_copy_helper_creates_helper_when_enabled
    with_temp_app do |dir|
      generator = build_generator(dir, link_helper: true)

      generator.copy_helper

      helper_path = File.join(dir, "app/helpers/recording_studio_accessible/access_management_helper.rb")
      assert File.exist?(helper_path)
      assert_includes File.read(helper_path), "recording_access_management_link"
    end
  end
end