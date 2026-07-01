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

  def test_copy_migrations_skips_when_core_access_is_present
    with_temp_app do |dir|
      generator = build_generator(dir)
      messages = []
      generator.stub(:say, ->(message, color = nil) { messages << [message, color] }) do
        RecordingStudioAccessible::Compatibility.stub(:core_access_present?, true) do
          generator.copy_migrations
        end
      end

      assert_equal [["RecordingStudio already provides access tables; skipping addon-owned access migrations.", :yellow]],
                   messages
      refute_path_exists File.join(dir, "db/migrate")
    end
  end

  def test_copy_migrations_copies_missing_migrations
    with_temp_app do |dir|
      generator = build_generator(dir)
      messages = []
      numbers = %w[20260101000000 20260101000001]
      generator.stub(:say, ->(message, color = nil) { messages << [message, color] }) do
        generator.stub(:next_migration_number, -> { numbers.shift }) do
          RecordingStudioAccessible::Compatibility.stub(:core_access_present?, false) do
            generator.copy_migrations
          end
        end
      end

      copied = Dir.glob(File.join(dir, "db/migrate/*.rb")).map { |path| File.basename(path) }
      assert_includes copied, "20260101000000_create_recording_studio_accesses.rb"
      assert_includes copied, "20260101000001_add_indexes_for_access_container_lookup.rb"
      assert_includes messages, ["Run 'bin/rails db:migrate' to apply the migrations.", :green]
    end
  end
end
