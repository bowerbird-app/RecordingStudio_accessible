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
end
