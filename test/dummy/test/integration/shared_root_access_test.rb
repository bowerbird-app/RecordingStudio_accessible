require_relative "../test_helper"

class SharedRootAccessIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_user("shared-root-admin@example.com")

    @message_root = MessageRoot.create!(name: "Shared Messages Root")
    @message_root_recording = create_root_recording(@message_root)
  end

  test "mounted access management is unavailable on shared roots" do
    sign_in @admin

    get "/recording_studio_accessible/recordings/#{@message_root_recording.id}/accesses"

    assert_response :not_found
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end
end
