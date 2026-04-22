# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  def setup
    @configuration = RecordingStudioAccessible::Configuration.new
  end

  def test_defaults_warn_on_core_conflict
    assert_equal true, @configuration.warn_on_core_conflict
  end

  def test_merge_updates_known_attributes
    @configuration.merge!(warn_on_core_conflict: false)

    assert_equal false, @configuration.warn_on_core_conflict
  end

  def test_merge_ignores_unknown_keys
    @configuration.merge!(unknown_key: "ignored")

    refute_respond_to @configuration, :unknown_key
  end

  def test_to_h_reports_registered_hook_counts
    @configuration.hooks.before_initialize { nil }
    @configuration.hooks.after_service { nil }

    result = @configuration.to_h

    assert_equal 1, result.fetch(:hooks_registered).fetch(:before_initialize)
    assert_equal 1, result.fetch(:hooks_registered).fetch(:after_service)
  end

  def test_access_management_configuration_is_customizable
    actor_scope = ->(_controller) { [:custom_actor] }
    actor_label = ->(actor) { "Label: #{actor}" }
    actor_email_resolver = ->(controller:, email:) { [controller, email] }
    authorizer = ->(controller:, recording:) { controller == :controller && recording == :recording }

    @configuration.access_management_actor_scope = actor_scope
    @configuration.access_management_actor_label = actor_label
    @configuration.access_management_actor_email_resolver = actor_email_resolver
    @configuration.access_management_authorizer = authorizer

    assert_equal [:custom_actor], @configuration.grantable_actors_for(controller: :controller)
    assert_equal "Label: custom_actor", @configuration.actor_label_for(:custom_actor)
    assert_equal [:controller, "person@example.com"],
                 @configuration.resolve_actor_for_email(controller: :controller, email: "person@example.com")
    assert @configuration.authorize_access_management?(controller: :controller, recording: :recording)
  end
end
