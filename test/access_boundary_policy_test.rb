# frozen_string_literal: true

require "test_helper"
require "recording_studio_accessible/extracted/recording_studio/services/access_boundary_policy"

class AccessBoundaryPolicyTest < Minitest::Test
  def test_returns_inherited_role_when_it_meets_boundary_minimum
    resolved_role = RecordingStudio::Services::AccessBoundaryPolicy.new(
      minimum_role: :edit,
      inherited_role: :admin
    ).resolved_role

    assert_equal :admin, resolved_role
  end

  def test_returns_nil_when_inherited_role_is_weaker_than_boundary_minimum
    resolved_role = RecordingStudio::Services::AccessBoundaryPolicy.new(
      minimum_role: :admin,
      inherited_role: :edit
    ).resolved_role

    assert_nil resolved_role
  end

  def test_returns_nil_when_boundary_has_no_minimum_role
    resolved_role = RecordingStudio::Services::AccessBoundaryPolicy.new(
      minimum_role: nil,
      inherited_role: :admin
    ).resolved_role

    assert_nil resolved_role
  end
end