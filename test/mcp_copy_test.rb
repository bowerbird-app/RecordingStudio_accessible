# frozen_string_literal: true

require "test_helper"
require "recording_studio_accessible/mcp_copy"

class McpCopyTest < Minitest::Test
  LEGACY_TOOL_NAMES = %w[
    grant_access
    list_access
    update_access
    revoke_access
    capability_action
    Workspace--list_access
    Workspace--grant_access
    Workspace--update_access
    Workspace--revoke_access
  ].freeze
  FORBIDDEN = /\b(?:view|edit|admin|accessible|permission)\b/i

  def test_names_come_from_the_public_type
    assert_equal "grant_access_to_press_kit", RecordingStudioAccessible::McpCopy.tool_name(:grant_access, "PressKit")
    assert_equal "list_access_to_press_kit",
                 RecordingStudioAccessible::McpCopy.tool_name(:list_access, "FeaturedIn::PressKit")
    assert_equal "update_access_to_press_kit",
                 RecordingStudioAccessible::McpCopy.tool_name(:update_access, "FeaturedIn::PressKit")
    assert_equal "revoke_access_to_press_kit",
                 RecordingStudioAccessible::McpCopy.tool_name(:revoke_access, "PressKit")

    name = RecordingStudioAccessible::McpCopy.tool_name(:grant_access, "FeaturedIn::PressKit")
    refute_includes name, "FeaturedIn"
    refute_includes name, "::"
    LEGACY_TOOL_NAMES.each { |legacy| refute_equal legacy, name }
  end

  def test_registration_is_per_type_and_skips_a_public_name_override
    registration = RecordingStudioAccessible::McpCopy.tool_registration(:grant_access, "PressKit")

    assert_equal "grant_access_to_press_kit", registration.fetch(:name)
    assert_equal "PressKit", registration.fetch(:type)
    assert_equal :grant_access, registration.fetch(:action)
    refute registration.key?(:public_name)
    refute registration.key?(:operation)
    refute registration.key?(:endpoint)
    assert_includes registration.fetch(:description), "must already exist"
    assert_includes registration.fetch(:description), "The role field is required."
    assert_includes registration.fetch(:description), "list_access_to_press_kit"
    refute_match FORBIDDEN, registration.fetch(:title)
    refute_match FORBIDDEN, registration.fetch(:description)
    refute_match(/\bAccess\b/, registration.fetch(:title))
    refute_match(/\bAccess\b/, registration.fetch(:description))
  end

  def test_register_is_a_no_op_when_mcp_is_not_loaded
    refute defined?(RecordingStudioMcp)
    refute RecordingStudioAccessible::McpCopy.mcp_available?
    assert_empty RecordingStudioAccessible::McpCopy.tool_names
    assert_nil RecordingStudioAccessible::McpCopy.register!
  end

  def test_gemspec_does_not_depend_on_recording_studio_mcp
    gemspec = File.read(File.expand_path("../recording_studio_accessible.gemspec", __dir__))
    entry = File.read(File.expand_path("../lib/recording_studio_accessible.rb", __dir__))

    refute_match(/add_dependency\s+"recording_studio_mcp"/, gemspec)
    refute_includes entry, 'require "recording_studio_mcp"'
  end
end
