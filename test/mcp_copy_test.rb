# frozen_string_literal: true

require "test_helper"
require "recording_studio_accessible/mcp_copy"

class McpCopyTest < Minitest::Test
  def test_register_is_a_no_op_when_mcp_is_not_loaded
    refute defined?(RecordingStudioMcp)
    refute RecordingStudioAccessible::McpCopy.mcp_available?
    assert_empty RecordingStudioAccessible::McpCopy.tool_names
    assert_nil RecordingStudioAccessible::McpCopy.register!
    assert_predicate RecordingStudioAccessible::McpCopy.type_label("FeaturedIn::PressKit"), :present?
  end

  def test_gemspec_does_not_depend_on_recording_studio_mcp
    gemspec = File.read(File.expand_path("../recording_studio_accessible.gemspec", __dir__))
    entry = File.read(File.expand_path("../lib/recording_studio_accessible.rb", __dir__))

    refute_match(/add_dependency\s+"recording_studio_mcp"/, gemspec)
    refute_includes entry, 'require "recording_studio_mcp"'
  end
end
