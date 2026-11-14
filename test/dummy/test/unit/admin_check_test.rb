# frozen_string_literal: true

require "test_helper"

class AdminCheckTest < ActiveSupport::TestCase
  setup do
    @configuration = RecordingStudioAccessible.configuration
    @original_resolver = @configuration.admin_root_resolver

    @viewer = create_user("admin-check-viewer@example.com")
    @editor = create_user("admin-check-editor@example.com")
    @owner = create_user("admin-check-owner@example.com")
    @stranger = create_user("admin-check-stranger@example.com")

    @workspace = Workspace.create!(name: "Admin check workspace")
    @root = create_root_recording(@workspace)
    @folder = Folder.create!(workspace: @workspace, name: "Admin check folder", summary: "Folder", position: 0)
    @child = create_child_recording(recordable: @folder, parent_recording: @root)

    create_direct_access_recording(actor: @viewer, role: :view, parent_recording: @root)
    create_direct_access_recording(actor: @editor, role: :edit, parent_recording: @root)
    create_direct_access_recording(actor: @owner, role: :admin, parent_recording: @root)

    @configuration.admin_root_resolver = -> { @root }
  end

  teardown do
    @configuration.admin_root_resolver = @original_resolver
    RecordingStudio.unregister_recording_filter(:admin_check_trash)
    RecordingStudio.unregister_recording_filter(:admin_check_exclude)
  end

  test "a fresh configuration leaves the resolver unset" do
    assert_nil RecordingStudioAccessible::Configuration.new.admin_root_resolver
  end

  test "an unset resolver returns no root and denies admin" do
    @configuration.admin_root_resolver = nil

    warnings = capture_warnings do
      assert_nil RecordingStudioAccessible.admin_root
      assert_equal false, RecordingStudioAccessible.admin?(actor: @owner)
    end

    assert_empty warnings
  end

  test "a non-callable resolver returns no root" do
    @configuration.admin_root_resolver = "not callable"

    assert_nil RecordingStudioAccessible.admin_root
    assert_equal false, RecordingStudioAccessible.admin?(actor: @owner)
  end

  test "a resolver that returns nil denies admin" do
    @configuration.admin_root_resolver = -> { nil }

    assert_nil RecordingStudioAccessible.admin_root
    assert_equal false, RecordingStudioAccessible.admin?(actor: @owner)
  end

  test "a resolver that returns a non-recording denies admin without a warning" do
    @configuration.admin_root_resolver = -> { "not a recording" }

    warnings = capture_warnings do
      assert_nil RecordingStudioAccessible.admin_root
      assert_equal false, RecordingStudioAccessible.admin?(actor: @owner)
    end

    assert_empty warnings
  end

  test "a resolver that raises returns nil and logs a warning" do
    @configuration.admin_root_resolver = -> { raise RuntimeError, "resolver broke" }

    warnings = capture_warnings do
      assert_nil RecordingStudioAccessible.admin_root
      assert_equal false, RecordingStudioAccessible.admin?(actor: @owner)
    end

    assert_equal 2, warnings.size
    warnings.each do |warning|
      assert_includes warning, "admin_root_resolver failed"
      assert_includes warning, "RuntimeError"
      assert_includes warning, "resolver broke"
    end
  end

  test "a zero-arg resolver ignores context and returns the kept root" do
    called = 0
    @configuration.admin_root_resolver = lambda do
      called += 1
      @root
    end

    assert_same @root, RecordingStudioAccessible.admin_root(context: { request_id: "abc" })
    assert_equal 1, called
  end

  test "a context resolver receives the context hash" do
    seen = nil
    @configuration.admin_root_resolver = lambda do |context:|
      seen = context
      @root
    end

    assert_same @root, RecordingStudioAccessible.admin_root
    assert_equal({}, seen)

    assert_same @root, RecordingStudioAccessible.admin_root(context: { request_id: "abc" })
    assert_equal({ request_id: "abc" }, seen)

    assert_equal true, RecordingStudioAccessible.admin?(actor: @viewer, context: { request_id: "from-admin" })
    assert_equal({ request_id: "from-admin" }, seen)
  end

  test "a child recording is not the admin root" do
    @configuration.admin_root_resolver = -> { @child }

    assert_nil RecordingStudioAccessible.admin_root
    assert_equal false, RecordingStudioAccessible.admin?(actor: @owner)
  end

  test "a root left out of Recording.kept is not the admin root" do
    RecordingStudio.register_recording_filter(
      :admin_check_exclude,
      sql: ->(table) { "#{table}.id IS NULL" }
    ) { |recordings| recordings.where.not(id: @root.id) }

    refute RecordingStudio::Recording.kept.exists?(id: @root.id)
    assert_nil RecordingStudioAccessible.admin_root
    assert_equal false, RecordingStudioAccessible.admin?(actor: @owner)
  end

  test "a trashed root is dropped when a kept filter hides trashed rows" do
    RecordingStudio.register_recording_filter(
      :admin_check_trash,
      sql: ->(table) { "#{table}.trashed_at IS NULL" }
    ) { |recordings| recordings.where(trashed_at: nil) }

    assert_same @root, RecordingStudioAccessible.admin_root

    @root.update_column(:trashed_at, Time.current)

    refute RecordingStudio::Recording.kept.exists?(id: @root.id)
    assert_nil RecordingStudioAccessible.admin_root
    assert_equal false, RecordingStudioAccessible.admin?(actor: @owner)
  end

  test "role levels follow the grant on the admin root" do
    assert_equal true, RecordingStudioAccessible.admin?(actor: @viewer, role: :view)
    assert_equal false, RecordingStudioAccessible.admin?(actor: @viewer, role: :edit)
    assert_equal false, RecordingStudioAccessible.admin?(actor: @viewer, role: :admin)

    assert_equal true, RecordingStudioAccessible.admin?(actor: @editor, role: :view)
    assert_equal true, RecordingStudioAccessible.admin?(actor: @editor, role: :edit)
    assert_equal false, RecordingStudioAccessible.admin?(actor: @editor, role: :admin)

    assert_equal true, RecordingStudioAccessible.admin?(actor: @owner, role: :view)
    assert_equal true, RecordingStudioAccessible.admin?(actor: @owner, role: :edit)
    assert_equal true, RecordingStudioAccessible.admin?(actor: @owner, role: :admin)
    assert_equal true, RecordingStudioAccessible.admin?(actor: @owner)
  end

  test "a missing actor, a stranger, and an invalid role are false" do
    assert_equal false, RecordingStudioAccessible.admin?(actor: nil)
    assert_equal false, RecordingStudioAccessible.admin?(actor: @stranger, role: :view)
    assert_equal false, RecordingStudioAccessible.admin?(actor: @owner, role: :download)
    assert_equal false, RecordingStudioAccessible.admin?(actor: @owner, role: nil)
  end

  test "an invalid role does not call authorized?" do
    called = false
    replacement = lambda do |**|
      called = true
      true
    end

    RecordingStudioAccessible.stub(:authorized?, replacement) do
      assert_equal false, RecordingStudioAccessible.admin?(actor: @owner, role: :download)
    end

    refute called
  end

  test "admin? uses the configured authorization service" do
    calls = []
    service = Class.new do
      define_singleton_method(:allowed?) do |actor:, recording:, role:|
        calls << [actor, recording, role]
        role.to_sym == :edit
      end
    end

    RecordingStudioAccessible::Authorization.stub(:authorization_service, service) do
      assert_equal true, RecordingStudioAccessible.admin?(actor: @stranger, role: :edit)
      assert_equal false, RecordingStudioAccessible.admin?(actor: @stranger, role: :view)
    end

    assert_equal [[@stranger, @root, :edit], [@stranger, @root, :view]], calls
  end

  test "a raised authorization error returns false and is logged" do
    replacement = lambda do |**|
      raise StandardError, "auth blew up"
    end

    warnings = []
    RecordingStudioAccessible.stub(:authorized?, replacement) do
      warnings = capture_warnings do
        assert_equal false, RecordingStudioAccessible.admin?(actor: @owner, role: :view)
      end
    end

    assert_equal 1, warnings.size
    assert_includes warnings.first, "admin? failed"
    assert_includes warnings.first, "auth blew up"
  end

  test "a raised role check returns false and is logged" do
    replacement = lambda do |*|
      raise StandardError, "role blew up"
    end

    warnings = []
    RecordingStudioAccessible.stub(:role_valid_for?, replacement) do
      warnings = capture_warnings do
        assert_equal false, RecordingStudioAccessible.admin?(actor: @owner)
      end
    end

    assert_equal 1, warnings.size
    assert_includes warnings.first, "admin? failed"
    assert_includes warnings.first, "role blew up"
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def capture_warnings
    messages = []
    logger = Object.new
    logger.define_singleton_method(:warn) { |message| messages << message.to_s }
    Rails.stub(:logger, logger) { yield }
    messages
  end
end
