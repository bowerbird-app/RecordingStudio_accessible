# frozen_string_literal: true

require "test_helper"
require "recording_studio_accessible/extracted/recording_studio/access_roles"

class AccessRolesTest < Minitest::Test
  def test_satisfies_returns_true_when_role_meets_minimum
    assert RecordingStudio::AccessRoles.satisfies?(role: :admin, minimum_role: :edit)
    assert RecordingStudio::AccessRoles.satisfies?(role: :edit, minimum_role: :edit)
  end

  def test_satisfies_returns_false_when_role_is_weaker_than_minimum
    refute RecordingStudio::AccessRoles.satisfies?(role: :view, minimum_role: :edit)
  end

  def test_satisfies_returns_false_for_unknown_roles
    refute RecordingStudio::AccessRoles.satisfies?(role: :owner, minimum_role: :edit)
    refute RecordingStudio::AccessRoles.satisfies?(role: :admin, minimum_role: :owner)
  end
end
