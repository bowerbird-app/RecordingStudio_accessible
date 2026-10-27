# frozen_string_literal: true

require "test_helper"

class ConfigurationDefaultResolversTest < ActiveSupport::TestCase
  setup do
    @configuration = RecordingStudioAccessible::Configuration.new
    @original_actor = Current.actor
  end

  teardown do
    Current.actor = @original_actor
  end

  test "default actor scope orders host users by email" do
    later = create_user("resolver-zeta@example.com")
    earlier = create_user("resolver-ada@example.com")

    actors = @configuration.grantable_actors_for(controller: :controller)
    emails = actors.map(&:email)

    assert_includes emails, earlier.email
    assert_includes emails, later.email
    assert_operator emails.index(earlier.email), :<, emails.index(later.email)
  end

  test "default actor email resolver uses a normalized email" do
    user = create_user("person@example.com")

    assert_equal user, @configuration.resolve_actor_for_email(
      controller: :controller,
      email: " PERSON@EXAMPLE.COM "
    )
  end

  test "default current actor prefers Current.actor" do
    user = create_user("resolver-current@example.com")
    Current.actor = user
    controller = Class.new do
      def current_user
        :controller_user
      end
    end.new

    assert_equal user, @configuration.current_actor_for(controller: controller)
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end
end
