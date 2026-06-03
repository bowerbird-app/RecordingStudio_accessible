# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"
require "generators/recording_studio_accessible/migrations/migrations_generator"

class MigrationsGeneratorTest < Minitest::Test
  def with_temp_app(&)
    Dir.mktmpdir(&)
  end

  def build_generator(destination_root, options = {})
    RecordingStudioAccessible::Generators::MigrationsGenerator.new([], options, destination_root: destination_root)
  end

  def test_migration_exists_matches_plain_existing_migration
    with_temp_app do |dir|
      FileUtils.mkdir_p(File.join(dir, "db/migrate"))
      FileUtils.touch(File.join(dir, "db/migrate/20260101000000_create_recording_studio_accesses.rb"))

      assert build_generator(dir).send(:migration_exists?, "create_recording_studio_accesses.rb")
    end
  end

  def test_migration_exists_matches_recording_studio_engine_suffixed_migration
    with_temp_app do |dir|
      FileUtils.mkdir_p(File.join(dir, "db/migrate"))
      FileUtils.touch(File.join(dir, "db/migrate/20260101000000_create_recording_studio_accesses.recording_studio.rb"))

      assert build_generator(dir).send(:migration_exists?, "create_recording_studio_accesses.rb")
    end
  end
end
