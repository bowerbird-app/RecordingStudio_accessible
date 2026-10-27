# frozen_string_literal: true

require_relative "../test_helper"

class CurrentActorResolverTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.find_by(email: "current-actor@example.com") ||
            User.create!(email: "current-actor@example.com", password: "Password",
                         password_confirmation: "Password")
    Current.actor = nil if defined?(Current) && Current.respond_to?(:actor=)
  end

  teardown do
    Current.actor = nil if defined?(Current) && Current.respond_to?(:actor=)
  end

  test "signed in dummy controller resolves the actor from Current.actor" do
    sign_in @user

    get root_path

    assert_response :success
    assert_kind_of HomeController, @controller
    assert_equal @user, Current.actor
    assert_equal @user, RecordingStudioAccessible.configuration.current_actor_for(controller: @controller)
  end
end
