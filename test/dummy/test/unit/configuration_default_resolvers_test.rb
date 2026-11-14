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

  test "actor scope is required and does not list every user" do
    error = assert_raises(RecordingStudioAccessible::ConfigurationError) do
      @configuration.grantable_actors_for(controller: :controller)
    end

    assert_equal RecordingStudioAccessible::Copy.t("errors.actor_scope_required"), error.message
  end

  test "configured actor scope orders host users by email" do
    later = create_user("resolver-zeta@example.com")
    earlier = create_user("resolver-ada@example.com")
    @configuration.access_management_actor_scope = ->(_controller) { User.order(:email) }

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

  test "default actor label uses a recording studio user profile full name" do
    user = create_user("label-ada@example.com")
    RecordingStudioUser.record_profile!(user, actor: user, first_name: "Ada", last_name: "Lovelace")

    assert_equal "Ada Lovelace", @configuration.actor_label_for(user)
  end

  test "default actor avatar uses the dummy admin photo" do
    user = create_user("admin@admin.com")

    assert_equal User::DEMO_AVATAR_PATH, @configuration.actor_avatar_src_for(user)
  end

  test "default actor avatar is nil when the dummy user has no photo" do
    user = create_user("resolver-no-photo@example.com")

    assert_nil @configuration.actor_avatar_src_for(user)
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
