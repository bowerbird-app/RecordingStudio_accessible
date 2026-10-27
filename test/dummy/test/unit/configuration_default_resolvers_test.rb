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
    mixed_case_email = "Person@Example.com"
    User.connection.execute(
      "UPDATE users SET email = #{User.connection.quote(mixed_case_email)} WHERE id = #{User.connection.quote(user.id)}"
    )
    user.reload

    original_where = User.method(:where)
    where_queries = []

    User.stub(:where, lambda { |*args|
      where_queries << args
      original_where.call(*args)
    }) do
      assert_equal user, @configuration.resolve_actor_for_email(
        controller: :controller,
        email: " PERSON@EXAMPLE.COM "
      )
    end

    assert_equal mixed_case_email, user.email
    assert_equal [ "LOWER(email) = ?", "person@example.com" ], where_queries.sole
  end

  test "default actor email resolver uses find_by when where is unavailable" do
    user = create_user("person@example.com")
    original_respond_to = User.method(:respond_to?)
    original_find_by = User.method(:find_by)
    find_by_calls = []

    User.stub(:respond_to?, lambda { |name, include_all = false|
      return false if name.to_sym == :where

      original_respond_to.call(name, include_all)
    }) do
      User.stub(:find_by, lambda { |*args, **kwargs|
        find_by_calls << (kwargs.empty? ? args.first : kwargs)
        original_find_by.call(*args, **kwargs)
      }) do
        assert_equal user, @configuration.resolve_actor_for_email(
          controller: :controller,
          email: " PERSON@EXAMPLE.COM "
        )
      end
    end

    assert_equal [{ email: "person@example.com" }], find_by_calls
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
