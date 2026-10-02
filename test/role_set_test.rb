# frozen_string_literal: true

require "test_helper"

class RoleSetTest < Minitest::Test
  def test_default_roles_stay_view_edit_admin_in_that_order
    assert_equal %w[view edit admin], RecordingStudioAccessible.roles_for(nil)
    assert_equal({ "view" => 0, "edit" => 1, "admin" => 2 }, RecordingStudio::AccessRoles::ORDER)
    assert RecordingStudio::AccessRoles.satisfies?(role: :admin, minimum_role: :edit)
    assert RecordingStudio::AccessRoles.satisfies?(role: :edit, minimum_role: :view)
    refute RecordingStudio::AccessRoles.satisfies?(role: :view, minimum_role: :edit)
    refute RecordingStudioAccessible.role_valid_for?(nil, :download)
  end

  def test_a_context_can_declare_one_role
    recording = recording_for(:member)

    assert_equal %w[member], RecordingStudioAccessible.roles_for(recording)
    assert RecordingStudioAccessible.role_valid_for?(recording, :member)
    refute RecordingStudioAccessible.role_valid_for?(recording, :view)
  end

  def test_a_context_can_declare_two_roles
    recording = recording_for(:view, :download)

    assert_equal %w[view download], RecordingStudioAccessible.roles_for(recording)
    assert RecordingStudioAccessible.role_valid_for?(recording, "download")
    refute RecordingStudioAccessible.role_valid_for?(recording, :edit)
    refute RecordingStudioAccessible.role_valid_for?(recording, :admin)
  end

  def test_a_context_can_declare_three_roles
    recording = recording_for(:reader, :publisher, :owner)

    assert_equal %w[reader publisher owner], RecordingStudioAccessible.roles_for(recording)
    assert RecordingStudioAccessible.role_valid_for?(recording, :publisher)
    refute RecordingStudioAccessible.role_valid_for?(recording, :admin)
  end

  def test_a_context_can_declare_four_roles
    recording = recording_for(:view, :comment, :download, :admin)

    assert_equal %w[view comment download admin], RecordingStudioAccessible.roles_for(recording)
    assert RecordingStudioAccessible.role_valid_for?(recording, :comment)
    refute RecordingStudioAccessible.role_valid_for?(recording, :edit)
  end

  def test_role_declarations_stay_on_the_class_that_declared_them
    library = recording_for(:view, :download)
    workspace = recording_for(:view, :edit, :admin)

    assert RecordingStudioAccessible.role_valid_for?(library, :download)
    refute RecordingStudioAccessible.role_valid_for?(workspace, :download)
    assert RecordingStudioAccessible.role_valid_for?(workspace, :edit)
    refute RecordingStudioAccessible.role_valid_for?(library, :edit)
  end

  def test_declaration_rejects_an_empty_list_blank_names_and_duplicates
    assert_raises(ArgumentError) { declare_context }
    assert_raises(ArgumentError) { declare_context(nil) }
    assert_raises(ArgumentError) { declare_context(" ") }
    assert_raises(ArgumentError) { declare_context(:view, :view) }
    assert_raises(ArgumentError) { declare_context(:view, "view") }
  end

  private

  def recording_for(*names)
    Struct.new(:recordable).new(declare_context(*names).new)
  end

  def declare_context(*names)
    Class.new do
      extend RecordingStudioAccessible::RoleDeclaration

      accessible_roles(*names)
    end
  end
end
