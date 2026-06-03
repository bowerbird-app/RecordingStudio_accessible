require_relative "../test_helper"

class RecordingStudioAccessTest < ActiveSupport::TestCase
  test "direct access creation is blocked" do
    user = create_user("direct-access-blocked@example.com")

    assert_no_difference -> { RecordingStudio::Access.count } do
      error = assert_raises(ActiveRecord::RecordInvalid) do
        RecordingStudio::Access.create!(actor: user, role: :view)
      end

      assert_includes error.record.errors.full_messages.join, "Create access grants through RecordingStudioAccessible.grant_access"
    end
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end
end
