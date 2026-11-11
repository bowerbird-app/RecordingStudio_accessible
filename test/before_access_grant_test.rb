# frozen_string_literal: true

require "test_helper"

class BeforeAccessGrantTest < Minitest::Test
  def setup
    @previous = RecordingStudioAccessible.configuration.before_access_grant
  end

  def teardown
    RecordingStudioAccessible.configuration.before_access_grant = @previous
  end

  def test_nil_hook_is_a_no_op
    RecordingStudioAccessible.configuration.before_access_grant = nil
    context = RecordingStudioAccessible::GrantContext.new(
      actor: nil, recording: nil, role: :view, source: :grant
    )

    assert_nil RecordingStudioAccessible::BeforeAccessGrant.call!(context)
  end

  def test_bootstrap_source_does_not_call_the_hook
    called = false
    RecordingStudioAccessible.configuration.before_access_grant = ->(_context) { called = true }
    context = RecordingStudioAccessible::GrantContext.new(
      actor: nil, recording: nil, role: :admin, source: :bootstrap
    )

    RecordingStudioAccessible::BeforeAccessGrant.call!(context)
    refute called
  end

  def test_other_errors_propagate
    RecordingStudioAccessible.configuration.before_access_grant = ->(_context) { raise "boom" }
    context = RecordingStudioAccessible::GrantContext.new(
      actor: nil, recording: nil, role: :view, source: :grant
    )

    error = assert_raises(RuntimeError) { RecordingStudioAccessible::BeforeAccessGrant.call!(context) }
    assert_equal "boom", error.message
  end
end
