# frozen_string_literal: true

require "test_helper"

class ControllerAuthTest < Minitest::Test
  def test_exposes_controller_auth_as_a_reusable_concern
    assert defined?(RecordingStudioAccessible::ControllerAuth)
    assert_includes RecordingStudioAccessible::ControllerAuth.singleton_class.ancestors,
                    ActiveSupport::Concern
  end
end
