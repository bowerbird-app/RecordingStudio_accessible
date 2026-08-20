# frozen_string_literal: true

require "test_helper"

class SharedRootAccessTest < Minitest::Test
  Recording = Struct.new(:id, :recordable_type)

  def test_target_returns_false_without_recording_studio
    hide_recording_studio do
      refute RecordingStudioAccessible::SharedRootAccess.target?(Recording.new(1, "MessageRoot"))
    end
  end

  def test_target_returns_false_for_blank_recording
    refute RecordingStudioAccessible::SharedRootAccess.target?(nil)
    refute RecordingStudioAccessible::SharedRootAccess.target?("")
  end

  def test_target_delegates_to_recording_studio_shared_root_predicate
    recording = Recording.new(1, "MessageRoot")

    RecordingStudio.stub(:shared_root?, true) do
      assert RecordingStudioAccessible::SharedRootAccess.target?(recording)
    end

    RecordingStudio.stub(:shared_root?, false) do
      RecordingStudio.stub(:shared_root_type?, false) do
        refute RecordingStudioAccessible::SharedRootAccess.target?(recording)
      end
    end
  end

  def test_target_also_checks_shared_root_type
    recording = Recording.new(1, "MessageRoot")

    RecordingStudio.stub(:shared_root?, false) do
      RecordingStudio.stub(:shared_root_type?, true) do
        assert RecordingStudioAccessible::SharedRootAccess.target?(recording)
      end
    end
  end

  private

  def hide_recording_studio
    original = Object.const_get(:RecordingStudio)
    Object.send(:remove_const, :RecordingStudio)
    yield
  ensure
    Object.const_set(:RecordingStudio, original) unless Object.const_defined?(:RecordingStudio)
  end
end
