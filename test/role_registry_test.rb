# frozen_string_literal: true

require "test_helper"

class RoleRegistryTest < Minitest::Test
  def setup
    @names = %w[RankedRoleKit RankedRoleAlbum RankedRoleClash]
    RecordingStudioAccessible::RoleRegistry.reset!
  end

  def teardown
    @names.each do |name|
      next unless Object.const_defined?(name)

      Object.const_get(name).clear_accessible_roles!
      Object.send(:remove_const, name)
    end
    RecordingStudioAccessible::RoleRegistry.reset!
  end

  def test_built_in_order_is_unchanged_until_a_type_declares_a_custom_role
    registry = RecordingStudioAccessible::RoleRegistry

    assert_equal({ "view" => 0, "edit" => 1, "admin" => 2 }, RecordingStudio::AccessRoles::ORDER)
    assert_equal 0, registry.global_rank(:view)
    assert_equal 1, registry.global_rank(:edit)
    assert_equal 2, registry.global_rank(:admin)
    assert_nil registry.global_rank(:download)
    refute registry.custom?
    assert RecordingStudio::AccessRoles.satisfies?(role: :admin, minimum_role: :edit)
    refute RecordingStudio::AccessRoles.satisfies?(role: :view, minimum_role: :edit)
    refute RecordingStudio::AccessRoles.satisfies?(role: :download, minimum_role: :view)
  end

  def test_declaration_order_ranks_a_custom_role_between_the_built_ins
    kit = declare(:RankedRoleKit, :view, :download, :edit, :admin)
    recording = Struct.new(:recordable_type).new("RankedRoleKit")
    registry = RecordingStudioAccessible::RoleRegistry

    assert_operator registry.global_rank(:download), :>, registry.global_rank(:view)
    assert_operator registry.global_rank(:download), :<, registry.global_rank(:edit)
    assert registry.rank_on(recording, :download)
    assert RecordingStudio::AccessRoles.satisfies?(role: :download, minimum_role: :view, recording: recording)
    refute RecordingStudio::AccessRoles.satisfies?(role: :download, minimum_role: :edit, recording: recording)
    assert RecordingStudio::AccessRoles.satisfies?(role: :admin, minimum_role: :download, recording: recording)
    assert_equal "download", RecordingStudio::AccessRoles.strongest(%w[view download], recording: recording)
    refute registry.declares?(Struct.new(:recordable_type).new("Workspace"), :download)
    assert kit.accessible_role_set.include?(:download)
  end

  def test_a_reversed_pair_raises_at_declaration
    declare(:RankedRoleKit, :view, :download, :edit, :admin)

    error = assert_raises(ArgumentError) { declare(:RankedRoleClash, :view, :edit, :download, :admin) }

    assert_match "conflict", error.message
    refute_includes RecordingStudioAccessible::RoleRegistry.types_declaring(:download), "RankedRoleClash"
  end

  def test_rank_sql_stays_the_built_in_case_until_a_custom_role_exists
    connection = quote_connection
    sql = RecordingStudioAccessible::RoleRegistry.rank_sql(connection, "acc.role")

    assert_includes sql, "WHEN 'view' THEN 0"
    assert_includes sql, "WHEN 'edit' THEN 1"
    assert_includes sql, "WHEN 'admin' THEN 2"
    refute_includes sql, "recordable_type"

    declare(:RankedRoleKit, :view, :download, :edit, :admin)
    typed = RecordingStudioAccessible::RoleRegistry.rank_sql(connection, "acc.role", "parent.recordable_type")

    assert_includes typed, "parent.recordable_type = 'RankedRoleKit'"
    assert_includes typed, "WHEN 'download' THEN"
  end

  private

  def declare(const_name, *roles)
    Object.const_set(const_name, Class.new do
      extend RecordingStudioAccessible::RoleDeclaration
    end).tap { |klass| klass.accessible_roles(*roles) }
  end

  def quote_connection
    Object.new.tap do |connection|
      connection.define_singleton_method(:quote) { |value| "'#{value}'" }
    end
  end
end
