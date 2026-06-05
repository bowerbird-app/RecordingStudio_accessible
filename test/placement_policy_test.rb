# frozen_string_literal: true

require "test_helper"

class PlacementPolicyTest < Minitest::Test
  class RegisteredRecordable
    include RecordingStudioAccessible::AllowsAccessibleChildren
  end

  class RootRecordable
    include RecordingStudioAccessible::AllowsAccessibleChildren

    recording_studio_accessible_children :access
  end

  class PlainRecordable
    include RecordingStudioAccessible::AllowsAccessibleChildren
  end

  def test_opted_in_recordable_allows_access_children
    root_recording = Struct.new(:recordable).new(RootRecordable.new)

    assert RecordingStudioAccessible::PlacementPolicy.allowed_child_on_recording?(recording: root_recording,
                                                                                  child_type: :access)
  end

  def test_non_opted_in_recordable_rejects_access_children
    plain_recording = Struct.new(:recordable).new(PlainRecordable.new)

    refute RecordingStudioAccessible::PlacementPolicy.allowed_child_on_recording?(recording: plain_recording,
                                                                                  child_type: :access)
  end

  def test_unknown_child_type_raises_an_argument_error
    assert_raises(ArgumentError) do
      RootRecordable.allows_recording_studio_accessible_child?(:unknown)
    end
  end

  def test_access_child_declaration_enables_accessible_capability
    enabled = []

    RecordingStudio.stub(:enable_capability, ->(capability, on:) { enabled << [capability, on] }) do
      RegisteredRecordable.recording_studio_accessible_children :access, :access
    end

    assert_equal [[RecordingStudioAccessible::Compatibility::ACCESS_CAPABILITY, RegisteredRecordable]], enabled
    assert_equal [:access], RegisteredRecordable.recording_studio_accessible_child_types
  end

  def test_blank_child_declaration_does_not_enable_accessible_capability
    enabled = []

    RecordingStudio.stub(:enable_capability, ->(capability, on:) { enabled << [capability, on] }) do
      RegisteredRecordable.recording_studio_accessible_children nil
    end

    assert_empty enabled
    assert_empty RegisteredRecordable.recording_studio_accessible_child_types
  end
end
