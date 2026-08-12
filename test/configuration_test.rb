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

  def test_merge_updates_callable_avatar_resolver
    avatar_resolver = ->(actor) { { name: actor.to_s } }

    @configuration.merge!(avatar_resolver: avatar_resolver)

    assert_equal({ name: "custom_actor" }, @configuration.avatar_for(:custom_actor))
  end

  def test_merge_ignores_non_callable_avatar_resolver
    @configuration.merge!(avatar_resolver: "ignored")

    assert_nil @configuration.avatar_for(:custom_actor)
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

  def test_missing_actor_resolution_factory_methods
    found = RecordingStudioAccessible::MissingActorResolution.found(actor: :actor, notice: "found")
    created = RecordingStudioAccessible::MissingActorResolution.created(actor: :actor, notice: "created")
    invited = RecordingStudioAccessible::MissingActorResolution.invited(notice: "invited")
    invalid = RecordingStudioAccessible::MissingActorResolution.invalid(error: "invalid")
    redirect = RecordingStudioAccessible::MissingActorResolution.redirect(
      location: "/people/new",
      notice: "notice",
      alert: "alert",
      status: :requires_resolution
    )

    assert_equal :found, found.status
    assert_equal :actor, found.actor
    assert_equal "found", found.notice
    assert_equal :created, created.status
    assert_equal :actor, created.actor
    assert_equal "created", created.notice
    assert_equal :invited, invited.status
    assert_equal "invited", invited.notice
    assert_equal :invalid, invalid.status
    assert_equal "invalid", invalid.error
    assert_equal :requires_resolution, redirect.status
    assert_equal "/people/new", redirect.location
    assert_equal "notice", redirect.notice
    assert_equal "alert", redirect.alert
  end

  def test_access_actor_types_normalizes_strings_and_classes
    actor_class = Class.new do
      def self.base_class
        self
      end
    end
    actor_class.define_singleton_method(:name) { "Workspace" }

    @configuration.access_actor_types = ["User", actor_class, "", nil]

    assert_equal %w[User Workspace], @configuration.access_actor_types
  end

  def test_access_actor_types_uses_polymorphic_name_when_available
    actor_class = Class.new do
      def self.base_class
        self
      end

      def self.polymorphic_name
        "AccountMember"
      end
    end

    @configuration.access_actor_types = [actor_class]

    assert_equal ["AccountMember"], @configuration.access_actor_types
  end

  def test_nil_empty_and_blank_access_actor_types_reject_new_grants
    user = actor_named("User", id: 1)

    [nil, [], ["", nil]].each do |types|
      @configuration.access_actor_types = types

      refute @configuration.allowed_access_actor_type?(user)
    end
  end

  def test_allowed_access_actor_type_checks_normalized_actor_type_when_configured
    user = actor_named("User", id: 1)

    @configuration.access_actor_types = ["Workspace"]

    refute @configuration.allowed_access_actor_type?(user)

    @configuration.access_actor_types = ["User"]

    assert @configuration.allowed_access_actor_type?(user)
  end

  def test_all_access_actor_types_is_an_explicit_opt_in
    user = actor_named("User", id: 1)

    @configuration.access_actor_types = :all

    assert_equal :all, @configuration.access_actor_types
    assert @configuration.all_access_actor_types_allowed?
    assert @configuration.allowed_access_actor_type?(user)
  end

  def test_all_like_strings_do_not_allow_every_actor_type
    user = actor_named("User", id: 1)

    ["all", "*", true].each do |types|
      @configuration.access_actor_types = types

      refute @configuration.all_access_actor_types_allowed?
      refute @configuration.allowed_access_actor_type?(user)
    end
  end

  def test_nil_and_unpersisted_actors_are_rejected
    @configuration.access_actor_types = :all
    unpersisted_actor = actor_named("User", id: 1)
    unpersisted_actor.define_singleton_method(:persisted?) { false }

    refute @configuration.allowed_access_actor_type?(nil)
    refute @configuration.allowed_access_actor_type?(actor_named("User", id: nil))
    refute @configuration.allowed_access_actor_type?(unpersisted_actor)
  end

  def test_default_authorize_actor_through_only_allows_same_actor_identity
    actor_class = Class.new do
      def self.base_class
        self
      end
    end
    actor_class.define_singleton_method(:name) { "User" }

    actor = actor_class.new
    actor.define_singleton_method(:id) { 1 }
    same_actor = actor_class.new
    same_actor.define_singleton_method(:id) { 1 }
    other_actor = actor_class.new
    other_actor.define_singleton_method(:id) { 2 }

    assert @configuration.authorize_actor_through?(actor: actor, through: same_actor)
    refute @configuration.authorize_actor_through?(actor: actor, through: other_actor)
  end

  def test_configured_authorize_actor_through_receives_context
    calls = []
    @configuration.authorize_actor_through = lambda do |actor:, through:, recording:, role:, controller:, **extra|
      calls << [actor, through, recording, role, controller, extra]
      true
    end

    assert @configuration.authorize_actor_through?(
      actor: :actor,
      through: :through,
      recording: :recording,
      role: :edit,
      controller: :controller,
      extra: :value
    )
    assert_equal [[:actor, :through, :recording, :edit, :controller, { extra: :value }]], calls
  end

  def test_authorize_actor_through_fails_closed_when_hook_raises
    @configuration.authorize_actor_through = ->(**) { raise "boom" }

    refute @configuration.authorize_actor_through?(actor: :actor, through: :through)
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

  def test_avatar_resolver_defaults_to_nil
    assert_nil @configuration.avatar_for(:actor)
  end

  def test_avatar_resolver_normalizes_flatpack_avatar_data
    @configuration.avatar_resolver = lambda do |actor|
      {
        name: "Label: #{actor}",
        image_url: "https://example.com/avatar.png",
        alt: "Avatar for #{actor}",
        status: :online,
        ignored: "ignored"
      }
    end

    assert_equal(
      {
        name: "Label: custom_actor",
        alt: "Avatar for custom_actor",
        src: "https://example.com/avatar.png",
        status: :online
      },
      @configuration.avatar_for(:custom_actor)
    )
  end

  def test_avatar_resolver_drops_unsafe_urls
    @configuration.avatar_resolver = lambda do |_actor|
      {
        name: "Unsafe",
        image_url: "data:text/html,<script>alert(1)</script>",
        href: "javascript:alert(1)"
      }
    end

    assert_equal({ name: "Unsafe" }, @configuration.avatar_for(:custom_actor))
  end

  def test_avatar_resolver_drops_invalid_urls_and_protocol_relative_urls
    @configuration.avatar_resolver = lambda do |_actor|
      {
        name: "Invalid",
        image_url: "http://[invalid",
        href: "//example.com/people/1"
      }
    end

    assert_equal({ name: "Invalid" }, @configuration.avatar_for(:custom_actor))
  end

  def test_avatar_resolver_keeps_safe_image_and_relative_href_urls
    @configuration.avatar_resolver = lambda do |_actor|
      {
        name: "Safe",
        image_url: "https://cdn.example.com/avatar.png",
        href: "/people/1"
      }
    end

    assert_equal(
      { name: "Safe", src: "https://cdn.example.com/avatar.png", href: "/people/1" },
      @configuration.avatar_for(:custom_actor)
    )
  end

  def test_avatar_resolver_ignores_blank_hashes
    @configuration.avatar_resolver = ->(_actor) { { name: "", image_url: nil } }

    assert_nil @configuration.avatar_for(:custom_actor)
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

  def test_default_missing_actor_handler_reports_blank_email_as_required
    missing_actor_resolution = @configuration.resolve_missing_actor(
      controller: :controller,
      email: "  ",
      recording: :recording,
      role: :view,
      manager_actor: :manager
    )

    assert_equal :invalid, missing_actor_resolution.status
    assert_equal "User is required", missing_actor_resolution.error
  end

  def test_missing_actor_resolution_normalizes_hash_statuses
    @configuration.access_management_missing_actor_handler = lambda do |**|
      { status: :invited, notice: "Invitation sent" }
    end

    invited = @configuration.resolve_missing_actor(
      controller: :controller,
      email: "person@example.com",
      recording: :recording,
      role: :view,
      manager_actor: :manager
    )

    assert_equal :invited, invited.status
    assert_equal "Invitation sent", invited.notice

    @configuration.access_management_missing_actor_handler = lambda do |**|
      { status: :requires_resolution }
    end

    invalid = @configuration.resolve_missing_actor(
      controller: :controller,
      email: "person@example.com",
      recording: :recording,
      role: :view,
      manager_actor: :manager
    )

    assert_equal :invalid, invalid.status
    assert_equal "User with email person@example.com was not found", invalid.error
  end

  def test_default_actor_scope_orders_users_by_email_when_available
    Object.new
    user_scope = Class.new do
      attr_reader :ordered_by

      def order(column)
        @ordered_by = column
        self
      end
    end.new
    user_class = Class.new do
      class << self
        attr_accessor :scope
      end

      def self.all
        scope
      end

      def self.column_names
        ["email"]
      end
    end
    user_class.scope = user_scope
    Object.const_set(:User, user_class)

    assert_equal [user_scope], @configuration.grantable_actors_for(controller: :controller)
    assert_equal :email, user_scope.ordered_by
  ensure
    Object.send(:remove_const, :User) if Object.const_defined?(:User, false) && Object.const_get(:User) == user_class
  end

  def test_default_actor_email_resolver_uses_normalized_email
    found_user = Object.new
    relation = Class.new do
      attr_reader :query, :email

      def initialize(found_user)
        @found_user = found_user
      end

      def where(query, email)
        @query = query
        @email = email
        self
      end

      def first
        @found_user
      end
    end.new(found_user)
    user_class = Class.new do
      class << self
        attr_accessor :relation
      end

      def self.column_names
        ["email"]
      end

      def self.where(query, email)
        relation.where(query, email)
      end
    end
    user_class.relation = relation
    Object.const_set(:User, user_class)

    assert_same found_user, @configuration.resolve_actor_for_email(controller: :controller, email: " PERSON@EXAMPLE.COM ")
    assert_equal "LOWER(email) = ?", relation.query
    assert_equal "person@example.com", relation.email
  ensure
    Object.send(:remove_const, :User) if Object.const_defined?(:User, false) && Object.const_get(:User) == user_class
  end

  def test_default_actor_email_resolver_uses_find_by_when_where_is_unavailable
    found_user = Object.new
    user_class = Class.new do
      class << self
        attr_accessor :email, :found_user
      end

      def self.column_names
        ["email"]
      end

      def self.find_by(email:)
        self.email = email
        found_user
      end
    end
    user_class.found_user = found_user
    Object.const_set(:User, user_class)

    assert_same found_user, @configuration.resolve_actor_for_email(controller: :controller, email: " PERSON@EXAMPLE.COM ")
    assert_equal "person@example.com", user_class.email
  ensure
    Object.send(:remove_const, :User) if Object.const_defined?(:User, false) && Object.const_get(:User) == user_class
  end

  def test_default_actor_label_uses_email_name_or_fallback
    email_actor = Struct.new(:email, :id).new(" person@example.com ", 1)
    name_actor = Struct.new(:name, :id).new(" Ada ", 2)
    fallback_class = Class.new do
      attr_reader :id

      def self.name
        "AccountMember"
      end

      def initialize(id)
        @id = id
      end
    end
    fallback_actor = fallback_class.new(3)

    assert_equal "person@example.com", @configuration.actor_label_for(email_actor)
    assert_equal "Ada", @configuration.actor_label_for(name_actor)
    assert_equal "AccountMember #3", @configuration.actor_label_for(fallback_actor)
  end

  def test_default_access_granted_notifier_sends_mail_when_actor_has_email
    actor = Struct.new(:email).new("person@example.com")
    mail = Object.new
    delivered = false
    mail.define_singleton_method(:deliver_now) { delivered = true }
    mailer = Class.new do
      class << self
        attr_reader :params
      end

      define_singleton_method(:with) do |params|
        @params = params
        self
      end

      def self.access_granted
        @mail
      end

      class << self
        attr_writer :mail
      end
    end
    mailer.mail = mail
    original_mailer = RecordingStudioAccessible.const_get(:AccessGrantedMailer) if
      RecordingStudioAccessible.const_defined?(:AccessGrantedMailer, false)
    RecordingStudioAccessible.send(:remove_const, :AccessGrantedMailer) if original_mailer
    RecordingStudioAccessible.const_set(:AccessGrantedMailer, mailer)

    @configuration.notify_access_granted(controller: :controller, recording: :recording, actor: actor, role: :view,
                                         manager_actor: :manager)

    assert delivered
    assert_equal :recording, mailer.params.fetch(:recording)
    assert_equal "You were given access", mailer.params.fetch(:subject)
  ensure
    RecordingStudioAccessible.send(:remove_const, :AccessGrantedMailer) if
      RecordingStudioAccessible.const_defined?(:AccessGrantedMailer, false) &&
      RecordingStudioAccessible.const_get(:AccessGrantedMailer) == mailer
    RecordingStudioAccessible.const_set(:AccessGrantedMailer, original_mailer) if defined?(original_mailer) && original_mailer
  end

  def test_default_authorizers_delegate_to_module_authorization
    RecordingStudioAccessible.stub(:authorized?, true) do
      assert @configuration.authorize_access_management?(recording: :recording, actor: :actor)
      assert @configuration.authorize_mounted_page?(controller: :controller, recording: :recording, actor: :actor)
    end
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

  def test_default_access_granted_url_tries_root_recording_recordable
    controller = ControllerStub.new(
      main_app: MainAppStub.new(
        workspace_url_value: "http://example.com/workspaces/root",
        root_url_value: "http://example.com/"
      )
    )
    root_recording = Struct.new(:recordable).new(:workspace)
    recording = Struct.new(:recordable, :root_recording).new(:missing_route, root_recording)

    access_url = @configuration.send(
      :default_access_management_access_granted_url_resolver,
      controller: controller,
      recording: recording,
      actor: :actor,
      role: :view,
      manager_actor: :manager
    )

    assert_equal "http://example.com/workspaces/root", access_url
  end

  def test_default_access_granted_subject_uses_recording_label_when_available
    recording = Struct.new(:recordable).new(:workspace)

    RecordingStudio::Labels.stub(:title_for, "Workspace Alpha") do
      assert_equal(
        "You were given access to Workspace Alpha",
        @configuration.access_granted_subject_for(
          controller: :controller,
          recording: recording,
          actor: :actor,
          role: :view,
          manager_actor: :manager
        )
      )
    end
  end

  def test_deliver_notification_uses_available_delivery_method
    delivered_now = false
    mail = Class.new do
      define_method(:deliver_now) { delivered_now = true }
    end.new

    @configuration.send(:deliver_notification, mail)

    assert delivered_now

    delivered_later = false
    later_mail = Class.new do
      define_method(:deliver_later) { delivered_later = true }
    end.new

    @configuration.send(:deliver_notification, later_mail)

    assert delivered_later
  end

  def test_access_management_authorizer_exceptions_fail_closed
    @configuration.access_management_authorizer = ->(**) { raise "boom" }

    refute @configuration.authorize_access_management?(recording: :recording, actor: :actor)
  end

  def test_mounted_page_authorizer_exceptions_fail_closed
    @configuration.mounted_page_authorizer = ->(**) { raise "boom" }

    refute @configuration.authorize_mounted_page?(controller: :controller, actor: :actor, recording: :recording)
  end

  private

  def actor_named(name, id:)
    actor_class = Struct.new(:id) do
      def self.base_class
        self
      end
    end
    actor_class.define_singleton_method(:name) { name }
    actor_class.new(id)
  end
end
