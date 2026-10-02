# frozen_string_literal: true

require "test_helper"

class RoleColumnMigrationCopyTest < Minitest::Test
  def test_dummy_migration_matches_the_engine_file
    engine = File.read(File.expand_path("../db/migrate/20261002000012_change_recording_studio_accesses_role_to_string.rb", __dir__))
    dummy = File.read(File.expand_path("../test/dummy/db/migrate/20261002000012_change_recording_studio_accesses_role_to_string.rb", __dir__))

    assert_equal engine, dummy
  end
end
