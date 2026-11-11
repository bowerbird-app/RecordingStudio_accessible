# frozen_string_literal: true

require "test_helper"

class GrantRefusedTest < Minitest::Test
  def test_uses_copy_by_default
    error = RecordingStudioAccessible::GrantRefused.new

    assert_kind_of RecordingStudioAccessible::Error, error
    assert_equal "This person can't be added right now.", error.message
    assert_equal error.message, RecordingStudioAccessible::Copy.t("errors.grant_refused")
    assert_nil error.redirect_to
  end

  def test_keeps_message_and_optional_redirect
    error = RecordingStudioAccessible::GrantRefused.new(
      "You've filled every seat.",
      redirect_to: "/plans"
    )

    assert_equal "You've filled every seat.", error.message
    assert_equal "/plans", error.redirect_to
  end
end
