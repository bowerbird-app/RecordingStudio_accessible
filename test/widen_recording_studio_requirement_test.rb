# frozen_string_literal: true

require "test_helper"
require_relative "support/widen_recording_studio_requirement"

class WidenRecordingStudioRequirementTest < Minitest::Test
  class FakeSpec
    prepend WidenRecordingStudioRequirement

    attr_reader :last_dependency

    def add_dependency(name, *requirements)
      @last_dependency = [name, requirements]
    end
  end

  def setup
    @spec = FakeSpec.new
  end

  def test_rewrites_recording_studio_requirements_that_do_not_mention_six
    @spec.add_dependency("recording_studio", "~> 4.2")

    assert_equal ["recording_studio", [">= 6.1.0"]], @spec.last_dependency
  end

  def test_keeps_recording_studio_requirements_that_already_allow_six
    @spec.add_dependency("recording_studio", ">= 6.1.0")

    assert_equal ["recording_studio", [">= 6.1.0"]], @spec.last_dependency
  end

  def test_leaves_other_gems_alone
    @spec.add_dependency("rails", "~> 8.1.0")

    assert_equal ["rails", ["~> 8.1.0"]], @spec.last_dependency
  end
end
