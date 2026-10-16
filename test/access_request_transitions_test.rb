# frozen_string_literal: true

require "test_helper"

class AccessRequestTransitionsTest < Minitest::Test
  Transitions = RecordingStudioAccessible::AccessRequestTransitions

  def test_each_status_can_move_to_the_other_two_only
    Transitions::STATUSES.each do |status|
      others = Transitions::STATUSES - [status]

      assert_equal others.sort, Transitions.targets_for(status).sort
      refute Transitions.allowed?(from: status, to: status)
      refute Transitions.allowed?(from: status, to: "withdrawn")
    end
  end

  def test_each_transition_has_a_hook_an_event_and_a_flash
    assert_equal :access_request_approved, Transitions.hook_for("approved")
    assert_equal :access_request_denied, Transitions.hook_for("denied")
    assert_equal :access_request_reopened, Transitions.hook_for("pending")
    assert_equal "approved", Transitions.event_for("approved")
    assert_equal "denied", Transitions.event_for("denied")
    assert_equal "reopened", Transitions.event_for("pending")
    assert_equal "reopened", Transitions.flash_key("pending")
    assert_nil Transitions.flash_key("withdrawn")
  end
end
