# frozen_string_literal: true

require "test_helper"

class PlacementPolicyTest < Minitest::Test
  class RootRecordable
    include RecordingStudioAccessible::AllowsAccessibleChildren

    recording_studio_accessible_children :access, :boundary
  end

  class PlainRecordable
    include RecordingStudioAccessible::AllowsAccessibleChildren
  end

  def test_opted_in_recordable_allows_access_and_boundary_children
    root_recording = Struct.new(:recordable).new(RootRecordable.new)

    assert RecordingStudioAccessible::PlacementPolicy.allowed_child_on_recording?(recording: root_recording,
                                                                                  child_type: :access)
    assert RecordingStudioAccessible::PlacementPolicy.allowed_child_on_recording?(recording: root_recording,
                                                                                  child_type: :boundary)
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
end
