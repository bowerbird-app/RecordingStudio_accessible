# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  MainAppStub = Struct.new(:workspace_url_value, :root_url_value, keyword_init: true) do
    def polymorphic_url(recordable)
      raise ActionController::UrlGenerationError, "missing route" unless recordable == :workspace

      workspace_url_value
    end

    def root_url
      root_url_value
    end
  end

  ControllerStub = Struct.new(:main_app, keyword_init: true)

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
    current_actor_resolver = ->(controller:) { [controller, :current_actor] }
    actor_label = ->(actor) { "Label: #{actor}" }
    actor_email_resolver = ->(controller:, email:) { [controller, email] }
    notifier_calls = []
    missing_actor_handler = lambda do |controller:, email:, recording:, role:, manager_actor:|
      {
        status: :requires_resolution,
        location: "/users/new?email=#{email}",
        alert: [controller, recording, role, manager_actor].join(":")
      }
    end
    access_granted_notifier = lambda do |controller:, recording:, actor:, role:, manager_actor:|
      notifier_calls << [controller, recording, actor, role, manager_actor]
    end
    authorizer = ->(controller:, recording:) { controller == :controller && recording == :recording }
    mounted_page_authorizer = lambda do |controller:, actor:, recording:|
      controller == :controller && actor == :actor && recording == :recording
    end

    @configuration.access_management_actor_scope = actor_scope
    @configuration.access_management_current_actor_resolver = current_actor_resolver
    @configuration.access_management_actor_label = actor_label
    @configuration.access_management_actor_email_resolver = actor_email_resolver
    @configuration.access_management_missing_actor_handler = missing_actor_handler
    @configuration.access_management_access_granted_notifier = access_granted_notifier
    @configuration.access_management_authorizer = authorizer
    @configuration.mounted_page_authorizer = mounted_page_authorizer

    assert_equal [:custom_actor], @configuration.grantable_actors_for(controller: :controller)
    assert_equal %i[controller current_actor], @configuration.current_actor_for(controller: :controller)
    assert_equal "Label: custom_actor", @configuration.actor_label_for(:custom_actor)
    assert_equal [:controller, "person@example.com"],
                 @configuration.resolve_actor_for_email(controller: :controller, email: "person@example.com")
    missing_actor_resolution = @configuration.resolve_missing_actor(
      controller: :controller,
      email: "person@example.com",
      recording: :recording,
      role: :view,
      manager_actor: :manager
    )

    assert_instance_of RecordingStudioAccessible::MissingActorResolution, missing_actor_resolution
    assert_equal :requires_resolution, missing_actor_resolution.status
    assert_equal "/users/new?email=person@example.com", missing_actor_resolution.location
    assert_equal "controller:recording:view:manager", missing_actor_resolution.alert
    @configuration.notify_access_granted(
      controller: :controller,
      recording: :recording,
      actor: :actor,
      role: :view,
      manager_actor: :manager
    )

    assert_equal [%i[controller recording actor view manager]], notifier_calls
    assert @configuration.authorize_access_management?(controller: :controller, recording: :recording)
    assert @configuration.authorize_mounted_page?(controller: :controller, actor: :actor, recording: :recording)
  end

  def test_missing_actor_resolution_normalizes_actor_return_values
    user = Object.new
    @configuration.access_management_missing_actor_handler = lambda do |**|
      user
    end

    missing_actor_resolution = @configuration.resolve_missing_actor(
      controller: :controller,
      email: "person@example.com",
      recording: :recording,
      role: :view,
      manager_actor: :manager
    )

    assert_equal :found, missing_actor_resolution.status
    assert_same user, missing_actor_resolution.actor
  end

  def test_default_missing_actor_handler_returns_invalid_resolution
    missing_actor_resolution = @configuration.resolve_missing_actor(
      controller: :controller,
      email: "missing@example.com",
      recording: :recording,
      role: :view,
      manager_actor: :manager
    )

    assert_equal :invalid, missing_actor_resolution.status
    assert_equal "User with email missing@example.com was not found", missing_actor_resolution.error
  end

  def test_default_current_actor_prefers_current_actor
    current_class = Class.new do
      class << self
        attr_accessor :actor
      end
    end

    Object.const_set(:Current, current_class)
    current_class.actor = :configured_actor

    controller = Class.new do
      def current_user
        :controller_user
      end
    end.new

    assert_equal :configured_actor, @configuration.current_actor_for(controller: controller)
  ensure
    current_class.actor = nil if defined?(current_class) && current_class.respond_to?(:actor=)
    if Object.const_defined?(:Current, false) && Object.const_get(:Current) == current_class
      Object.send(:remove_const, :Current)
    end
  end

  def test_default_current_actor_falls_back_to_controller_current_user
    controller = Class.new do
      def current_user
        :controller_user
      end
    end.new

    assert_equal :controller_user, @configuration.current_actor_for(controller: controller)
  end

  def test_default_access_granted_url_uses_recordable_route_when_available
    controller = ControllerStub.new(
      main_app: MainAppStub.new(
        workspace_url_value: "http://example.com/workspaces/1",
        root_url_value: "http://example.com/"
      )
    )
    recording = Struct.new(:recordable, :root_recording).new(:workspace, nil)

    access_url = @configuration.send(
      :default_access_management_access_granted_url_resolver,
      controller: controller,
      recording: recording,
      actor: :actor,
      role: :view,
      manager_actor: :manager
    )

    assert_equal "http://example.com/workspaces/1", access_url
  end

  def test_default_access_granted_url_falls_back_to_root_url_when_recordable_route_is_missing
    controller = ControllerStub.new(
      main_app: MainAppStub.new(
        workspace_url_value: "http://example.com/workspaces/1",
        root_url_value: "http://example.com/"
      )
    )
    recording = Struct.new(:recordable, :root_recording).new(:missing_route, nil)

    access_url = @configuration.send(
      :default_access_management_access_granted_url_resolver,
      controller: controller,
      recording: recording,
      actor: :actor,
      role: :view,
      manager_actor: :manager
    )

    assert_equal "http://example.com/", access_url
  end
end
