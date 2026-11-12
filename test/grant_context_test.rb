# frozen_string_literal: true

require "test_helper"

class GrantContextTest < Minitest::Test
  def test_freezes_and_exposes_fields
    actor = Object.new
    recording = Object.new
    granted_by = Object.new
    context = RecordingStudioAccessible::GrantContext.new(
      actor: actor,
      actor_type: "User",
      actor_id: 12,
      recording: recording,
      role: :edit,
      previous_role: :view,
      source: :grant,
      granted_by: granted_by
    )

    assert context.frozen?
    assert_equal actor, context.actor
    assert_equal "User", context.actor_type
    assert_equal 12, context.actor_id
    assert_equal recording, context.recording
    assert_equal "edit", context.role
    assert_equal "view", context.previous_role
    assert_equal :grant, context.source
    assert_equal granted_by, context.granted_by
  end

  def test_page_sources_allow_a_nil_role_and_grantee
    context = RecordingStudioAccessible::GrantContext.new(
      actor: nil,
      recording: :recording,
      role: nil,
      source: :new_access,
      granted_by: :manager
    )

    assert_nil context.role
    assert_nil context.actor
    assert_nil context.previous_role
    assert_equal :recording, context.recording
    assert_equal :new_access, context.source
    assert_equal :manager, context.granted_by
    assert_includes RecordingStudioAccessible::GrantContext::PAGE_SOURCES, :new_invitation
    refute_includes RecordingStudioAccessible::GrantContext::WRITE_SOURCES, :new_access
    refute_includes RecordingStudioAccessible::GrantContext::WRITE_SOURCES, :new_invitation
  end

  def test_rejects_unknown_source
    error = assert_raises(ArgumentError) do
      RecordingStudioAccessible::GrantContext.new(
        actor: nil,
        recording: nil,
        role: :view,
        source: :seats
      )
    end

    assert_match(/unknown grant source/, error.message)
  end
end
