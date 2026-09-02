# frozen_string_literal: true

require "test_helper"

class AccessRecordingDependentLifecycleTest < Minitest::Test
  class FakeRecording
    def self.after_update(*) = nil
    def self.after_destroy(*) = nil

    include RecordingStudioAccessible::AccessRecordingDependentLifecycle

    attr_accessor :id, :recordable_type, :moved_attributes

    def initialize(id:, recordable_type:)
      @id = id
      @recordable_type = recordable_type
      @moved_attributes = []
    end

    def saved_change_to_attribute?(attribute)
      Array(moved_attributes).include?(attribute.to_sym)
    end
  end

  def test_enqueues_void_job_for_an_access_recording
    recording = FakeRecording.new(id: "manager-id", recordable_type: "RecordingStudio::Access")
    enqueued = nil

    RecordingStudioAccessible::DependentAccess.stub(:column_available?, true) do
      RecordingStudioAccessible::VoidDependentAccessesJob.stub(:perform_later, ->(id) { enqueued = id }) do
        recording.send(:recording_studio_accessible_enqueue_void_dependents)
      end
    end

    assert_equal "manager-id", enqueued
  end

  def test_does_not_enqueue_for_non_access_recordings
    recording = FakeRecording.new(id: "workspace", recordable_type: "Workspace")
    enqueued = false

    RecordingStudioAccessible::VoidDependentAccessesJob.stub(:perform_later, ->(*) { enqueued = true }) do
      recording.send(:recording_studio_accessible_enqueue_void_dependents)
    end

    refute enqueued
  end

  def test_does_not_enqueue_without_a_recording_id
    recording = FakeRecording.new(id: nil, recordable_type: "RecordingStudio::Access")
    enqueued = false

    RecordingStudioAccessible::DependentAccess.stub(:column_available?, true) do
      RecordingStudioAccessible::VoidDependentAccessesJob.stub(:perform_later, ->(*) { enqueued = true }) do
        recording.send(:recording_studio_accessible_enqueue_void_dependents)
      end
    end

    refute enqueued
  end

  def test_does_not_enqueue_when_the_depends_on_column_is_unavailable
    recording = FakeRecording.new(id: "manager-id", recordable_type: "RecordingStudio::Access")
    enqueued = false

    RecordingStudioAccessible::DependentAccess.stub(:column_available?, false) do
      RecordingStudioAccessible::VoidDependentAccessesJob.stub(:perform_later, ->(*) { enqueued = true }) do
        recording.send(:recording_studio_accessible_enqueue_void_dependents)
      end
    end

    refute enqueued
  end

  def test_enqueues_void_job_with_moved_when_parent_or_root_changes
    %i[parent_recording_id root_recording_id].each do |attribute|
      recording = FakeRecording.new(id: "manager-id", recordable_type: "RecordingStudio::Access")
      recording.moved_attributes = [attribute]
      enqueued = nil

      RecordingStudioAccessible::DependentAccess.stub(:column_available?, true) do
        RecordingStudioAccessible::VoidDependentAccessesJob.stub(:perform_later, lambda { |id, **kwargs|
          enqueued = [id, kwargs]
        }) do
          recording.send(:recording_studio_accessible_enqueue_void_dependents)
        end
      end

      assert_equal ["manager-id", { moved: true }], enqueued, "expected moved: true for #{attribute}"
    end
  end

  def test_swallows_enqueue_errors
    recording = FakeRecording.new(id: "manager-id", recordable_type: "RecordingStudio::Access")

    RecordingStudioAccessible::DependentAccess.stub(:column_available?, true) do
      RecordingStudioAccessible::VoidDependentAccessesJob.stub(:perform_later, ->(*) { raise "queue down" }) do
        assert_nil recording.send(:recording_studio_accessible_enqueue_void_dependents)
      end
    end
  end
end
