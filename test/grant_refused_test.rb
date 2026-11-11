# frozen_string_literal: true

require "test_helper"

class GrantRefusedTest < Minitest::Test
  def test_uses_copy_by_default
    error = RecordingStudioAccessible::GrantRefused.new

    assert_kind_of RecordingStudioAccessible::Error, error
    assert_equal "This person can't be added right now.", error.message
    assert_equal error.message, RecordingStudioAccessible::Copy.t("errors.grant_refused")
    assert_nil error.cta_label
    assert_nil error.cta_path
  end

  def test_keeps_message_and_optional_cta
    error = RecordingStudioAccessible::GrantRefused.new(
      "You've filled every seat.",
      cta_label: "See options",
      cta_path: "/billing"
    )

    assert_equal "You've filled every seat.", error.message
    assert_equal "See options", error.cta_label
    assert_equal "/billing", error.cta_path
  end
end
