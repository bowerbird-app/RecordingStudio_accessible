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

  class OtherCapabilityRecordable
    def recordable_name
      "Other capability recordable"
    end
  end

  def test_opted_in_recordable_allows_access_children
    root_recording = Struct.new(:recordable, :recordable_type).new(RootRecordable.new, RootRecordable.name)

    RecordingStudio.stub(:parent_allowed?, true) do
      assert RecordingStudioAccessible::PlacementPolicy.allowed_child_on_recording?(recording: root_recording,
                                                                                    child_type: :access)
    end
  end

  def test_opted_in_recordable_rejects_access_when_core_rejects_parent
    root_recording = Struct.new(:recordable, :recordable_type).new(RootRecordable.new, RootRecordable.name)

    RecordingStudio.stub(:parent_allowed?, false) do
      refute RecordingStudioAccessible::PlacementPolicy.allowed_child_on_recording?(recording: root_recording,
                                                                                    child_type: :access)
    end
  end

  def test_non_opted_in_recordable_rejects_access_children
    plain_recording = Struct.new(:recordable, :recordable_type).new(PlainRecordable.new, PlainRecordable.name)

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

  def test_unrelated_capability_does_not_enable_direct_access_management
    original_registered_capabilities = RecordingStudio.registered_capabilities.transform_values(&:dup)
    original_capabilities = RecordingStudio.configuration.instance_variable_get(:@capabilities).transform_values(&:dup)

    RecordingStudio.register_capability(
      :unrelated_access_probe,
      source: "unrelated_access_probe",
      child_recordables: [RecordingStudioAccessible::Compatibility::ACCESS_RECORDABLE_TYPE]
    )
    RecordingStudio.enable_capability(:unrelated_access_probe, on: OtherCapabilityRecordable)

    recording = Struct.new(:recordable, :recordable_type).new(OtherCapabilityRecordable.new, OtherCapabilityRecordable.name)

    refute RecordingStudioAccessible::PlacementPolicy.allowed_child_on_recording?(recording: recording,
                                                                                  child_type: :access)
  ensure
    RecordingStudio.instance_variable_set(:@registered_capabilities, original_registered_capabilities)
    RecordingStudio.configuration.instance_variable_set(:@capabilities, original_capabilities)
  end
end
