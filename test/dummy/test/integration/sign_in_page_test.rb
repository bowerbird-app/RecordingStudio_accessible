require_relative "../test_helper"

class SignInPageTest < ActionDispatch::IntegrationTest
  test "sign in page loads the tailwind stylesheet" do
    get "/users/sign_in"

    assert_response :success
    assert_match %r{href="/assets/tailwind(?:-[^"]+)?\.css"}, @response.body
  end
end
