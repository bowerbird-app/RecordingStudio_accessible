# frozen_string_literal: true

require "test_helper"

class LastAdminErrorTest < Minitest::Test
  def test_last_admin_error_uses_copy_by_default
    error = RecordingStudioAccessible::LastAdminError.new

    assert_kind_of RecordingStudioAccessible::Error, error
    assert_equal "Add another admin before removing the last one.", error.message
    assert_equal error.message, RecordingStudioAccessible::Copy.t("errors.last_admin")
  end
end
