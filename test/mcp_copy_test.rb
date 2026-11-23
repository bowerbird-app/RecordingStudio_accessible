# frozen_string_literal: true

require "test_helper"
require "recording_studio_accessible/mcp_copy"

class McpCopyTest < Minitest::Test
  TOOL_NAMES = %w[list_access grant_access update_access revoke_access].freeze
  LEGACY_TOOL_NAMES = %w[
    capability_action
    Workspace--list_access
    Workspace--grant_access
    Workspace--update_access
    Workspace--revoke_access
  ].freeze
  FORBIDDEN = /\b(?:view|edit|admin|accessible|permission)\b/i

  def test_tool_names_are_the_four_access_actions
    assert_equal TOOL_NAMES, RecordingStudioAccessible::McpCopy.tool_names
    LEGACY_TOOL_NAMES.each do |name|
      refute_includes RecordingStudioAccessible::McpCopy.tool_names, name
    end
  end

  def test_registrations_omit_type_and_public_name
    RecordingStudioAccessible::McpCopy.tool_names.each do |name|
      registration = RecordingStudioAccessible::McpCopy.tool_registration(name)

      assert_equal name, registration.fetch(:name)
      assert_equal name.to_sym, registration.fetch(:action)
      refute registration.key?(:type)
      refute registration.key?(:public_name)
      refute registration.key?(:operation)
      refute registration.key?(:endpoint)
      assert_equal RecordingStudioAccessible::McpCopy::Copy::TITLES.fetch(name), registration.fetch(:title)
      assert_equal RecordingStudioAccessible::McpCopy::Copy::DESCRIPTIONS.fetch(name), registration.fetch(:description)
      assert_equal RecordingStudioAccessible::McpCopy::Copy::OUTPUTS.fetch(name), registration.fetch(:output)
      refute_empty registration.fetch(:output)
    end
  end

  def test_copy_states_write_prerequisites_and_skips_role_names
    copy = RecordingStudioAccessible::McpCopy::Copy

    %w[grant_access update_access revoke_access].each do |name|
      assert_includes copy::DESCRIPTIONS.fetch(name), "must already exist"
    end
    assert_includes copy::DESCRIPTIONS.fetch("list_access"), "does not change"

    (copy::TITLES.values + copy::DESCRIPTIONS.values + copy::OUTPUTS.values).each do |text|
      refute_match FORBIDDEN, text
    end
    copy::INPUTS.each_value do |fields|
      fields.each_value do |meta|
        refute_match FORBIDDEN, meta.fetch(:description)
      end
    end
  end

  def test_register_is_a_no_op_when_mcp_is_not_loaded
    refute defined?(RecordingStudioMcp)
    refute RecordingStudioAccessible::McpCopy.mcp_available?
    assert_nil RecordingStudioAccessible::McpCopy.register!
  end

  def test_gemspec_does_not_depend_on_recording_studio_mcp
    gemspec = File.read(File.expand_path("../recording_studio_accessible.gemspec", __dir__))
    entry = File.read(File.expand_path("../lib/recording_studio_accessible.rb", __dir__))

    refute_match(/add_dependency\s+"recording_studio_mcp"/, gemspec)
    assert_includes gemspec, '">= 0.45", "< 0.46"'
    refute_includes entry, 'require "recording_studio_mcp"'
  end
end
