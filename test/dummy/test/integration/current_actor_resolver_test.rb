# frozen_string_literal: true

require_relative "../test_helper"

class CurrentActorResolverTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.find_by(email: "current-actor@example.com") ||
            User.create!(email: "current-actor@example.com", password: "Password",
                         password_confirmation: "Password")
  end

  test "signed in dummy controller resolves the actor from Current.actor" do
    sign_in @user

    get current_actor_resolver_path

    assert_response :success
    assert_kind_of CurrentActorResolversController, @controller
    assert_match(/resolver=#{Regexp.escape(@user.email)}/, response.body)
    assert_match(/current_actor=#{Regexp.escape(@user.email)}/, response.body)
    assert_match(/current_user=#{Regexp.escape(@user.email)}/, response.body)
  end
end
