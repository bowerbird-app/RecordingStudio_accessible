# frozen_string_literal: true

require "test_helper"

class AccessManagementPolicyTest < Minitest::Test
  def setup
    @original_configuration = RecordingStudioAccessible.instance_variable_get(:@configuration)
    RecordingStudioAccessible.instance_variable_set(:@configuration, RecordingStudioAccessible::Configuration.new)
  end

  def teardown
    RecordingStudioAccessible.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_policy_passes_actor_without_controller
    authorizer_calls = []
    RecordingStudioAccessible.configuration.access_management_authorizer = lambda do |recording:, actor:, controller: nil|
      authorizer_calls << [recording, actor, controller]
      actor == :admin
    end

    assert RecordingStudioAccessible::AccessManagementPolicy.allowed?(recording: :recording, actor: :admin)
    refute RecordingStudioAccessible::AccessManagementPolicy.allowed?(recording: :recording, actor: :viewer)
    assert_equal [[:recording, :admin, nil], [:recording, :viewer, nil]], authorizer_calls
  end

  def test_policy_remains_compatible_with_controller_based_authorizer
    controller = Object.new
    RecordingStudioAccessible.configuration.access_management_authorizer = lambda do |controller:, recording:|
      controller.equal?(controller) && recording == :recording
    end

    assert RecordingStudioAccessible::AccessManagementPolicy.allowed?(
      recording: :recording,
      actor: :admin,
      controller: controller
    )
  end
end
