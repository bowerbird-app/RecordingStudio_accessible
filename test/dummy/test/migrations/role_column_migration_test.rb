# frozen_string_literal: true

require_relative "../test_helper"

class RoleColumnMigrationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  ENGINE_MIGRATION = File.expand_path("../../../../db/migrate/20261002000012_change_recording_studio_accesses_role_to_string.rb", __dir__)

  setup do
    load ENGINE_MIGRATION
    @connection = ActiveRecord::Base.connection
    @migration = ChangeRecordingStudioAccessesRoleToString.new
    @migration.verbose = false
  end

  teardown do
    restore_saved_table
    RecordingStudio::Access.reset_column_information
    @connection.schema_cache.clear!
  end

  test "up converts legacy 0, 1, and 2" do
    with_table(:integer, [0, 1, 2]) do
      @migration.up

      assert_equal %w[admin edit view], role_values
      assert_equal "character varying", role_data_type
    end
  end

  test "up aborts when a legacy role is not 0, 1, or 2 and leaves the rows unchanged" do
    with_table(:integer, [0, 9]) do
      before = role_values

      error = assert_raises(ActiveRecord::IrreversibleMigration) { @migration.up }

      assert_includes error.message, "9"
      assert_equal before, role_values
      assert_equal "integer", role_data_type
      refute_includes role_values, "view"
    end
  end

  test "down converts view, edit, and admin" do
    with_table(:string, %w[view edit admin]) do
      @migration.down

      assert_equal %w[0 1 2], role_values
      assert_equal "integer", role_data_type
    end
  end

  test "down aborts when a custom role exists and leaves download unchanged" do
    with_table(:string, %w[view download]) do
      before = role_values

      error = assert_raises(ActiveRecord::IrreversibleMigration) { @migration.down }

      assert_includes error.message, "download"
      assert_equal before, role_values
      assert_equal "character varying", role_data_type
      assert_includes role_values, "download"
      refute_includes role_values, "0"
    end
  end

  private

  def with_table(type, values)
    @connection.transaction do
      install_table(type, values)
      yield
      raise ActiveRecord::Rollback
    end
  end

  def install_table(type, values)
    @connection.rename_table :recording_studio_accesses, :recording_studio_accesses_saved
    @connection.create_table :recording_studio_accesses, id: :uuid, default: -> { "gen_random_uuid()" } do |table|
      table.public_send(type, :role, null: false)
    end
    values.each do |value|
      @connection.insert("INSERT INTO recording_studio_accesses (role) VALUES (#{@connection.quote(value)})")
    end
    RecordingStudio::Access.reset_column_information
  end

  def restore_saved_table
    return unless @connection&.table_exists?(:recording_studio_accesses_saved)

    @connection.drop_table :recording_studio_accesses if @connection.table_exists?(:recording_studio_accesses)
    @connection.rename_table :recording_studio_accesses_saved, :recording_studio_accesses
  end

  def role_values
    @connection.select_values("SELECT role::text FROM recording_studio_accesses ORDER BY role::text")
  end

  def role_data_type
    @connection.select_value(<<~SQL.squish)
      SELECT data_type FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'recording_studio_accesses'
        AND column_name = 'role'
    SQL
  end
end
