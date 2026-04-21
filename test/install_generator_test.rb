# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"
require "generators/recording_studio_accessible/install/install_generator"

class InstallGeneratorTest < Minitest::Test
  def with_temp_app
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "app/assets/tailwind"))
      yield dir
    end
  end

  def build_generator(destination_root, options = {})
    RecordingStudioAccessible::Generators::InstallGenerator.new([], options, destination_root: destination_root)
  end

  def test_mount_engine_uses_default_mount_path
    generator = build_generator("/tmp")
    routes = []

    generator.stub(:route, ->(value) { routes << value }) do
      generator.mount_engine
    end

    assert_equal ['mount RecordingStudioAccessible::Engine, at: "/recording_studio_accessible"'], routes
  end

  def test_mount_engine_uses_configured_mount_path
    generator = build_generator("/tmp", mount_path: "/addons/access")
    routes = []

    generator.stub(:route, ->(value) { routes << value }) do
      generator.mount_engine
    end

    assert_equal ['mount RecordingStudioAccessible::Engine, at: "/addons/access"'], routes
  end

  def test_add_tailwind_source_injects_engine_and_flatpack_sources
    with_temp_app do |dir|
      css_path = File.join(dir, "app/assets/tailwind/application.css")
      File.write(css_path, "@import \"tailwindcss\";\n")

      generator = build_generator(dir)

      Rails.stub(:root, Pathname.new(dir)) do
        generator.stub(:say, nil) { generator.add_tailwind_source }
      end

      css = File.read(css_path)
      tailwind_source_lines.each { |line| assert_includes css, line }
    end
  end

  private

  def tailwind_source_lines
    [
      '@source "../../vendor/bundle/**/recording_studio_accessible/app/views/**/*.erb";',
      '@source "../../../../../../usr/local/bundle/ruby/**/bundler/gems/recording_studio_accessible-*/app/views/**/*.erb";',
      '@source "../../vendor/bundle/**/flatpack/app/components/**/*.{rb,erb}";',
      '@source "../../../../../../usr/local/bundle/ruby/**/bundler/gems/flatpack-*/app/components/**/*.{rb,erb}";'
    ]
  end
end
