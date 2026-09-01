# frozen_string_literal: true

require "test_helper"

class DependentAccessTest < Minitest::Test
  Recording = Struct.new(:id, :recordable_type, :recordable, :trashed_at, :root_id, keyword_init: true)
  AccessRecordable = Struct.new(:role, :depends_on_recording_id, keyword_init: true)

  def test_independent_grants_are_effective
    access_recording = Recording.new(id: 1, recordable: AccessRecordable.new(role: "admin"))

    assert RecordingStudioAccessible::DependentAccess.effective?(access_recording)
  end

  def test_effective_fails_closed_when_manager_is_missing
    access_recording = Recording.new(
      id: 1,
      recordable: AccessRecordable.new(role: "view", depends_on_recording_id: "missing")
    )

    RecordingStudio::Recording.stub(:unscoped, recording_finder(nil)) do
      refute RecordingStudioAccessible::DependentAccess.effective?(access_recording)
    end
  end

  def test_effective_fails_closed_when_manager_is_trashed
    manager = Recording.new(
      id: 2,
      recordable_type: "RecordingStudio::Access",
      recordable: AccessRecordable.new(role: "admin"),
      trashed_at: Time.now,
      root_id: 10
    )
    access_recording = Recording.new(
      id: 1,
      recordable: AccessRecordable.new(role: "view", depends_on_recording_id: 2),
      root_id: 10
    )

    RecordingStudio.stub(:root_recording_id_for, lambda(&:root_id)) do
      RecordingStudio::Recording.stub(:unscoped, recording_finder(manager)) do
        refute RecordingStudioAccessible::DependentAccess.effective?(access_recording)
      end
    end
  end

  def test_effective_fails_closed_when_manager_role_is_weaker
    manager = Recording.new(
      id: 2,
      recordable_type: "RecordingStudio::Access",
      recordable: AccessRecordable.new(role: "view"),
      root_id: 10
    )
    access_recording = Recording.new(
      id: 1,
      recordable: AccessRecordable.new(role: "admin", depends_on_recording_id: 2),
      root_id: 10
    )

    RecordingStudio.stub(:root_recording_id_for, lambda(&:root_id)) do
      RecordingStudio::Recording.stub(:unscoped, recording_finder(manager)) do
        refute RecordingStudioAccessible::DependentAccess.effective?(access_recording)
      end
    end
  end

  def test_effective_allows_a_capped_dependent_on_the_same_root
    manager = Recording.new(
      id: 2,
      recordable_type: "RecordingStudio::Access",
      recordable: AccessRecordable.new(role: "edit"),
      root_id: 10
    )
    access_recording = Recording.new(
      id: 1,
      recordable: AccessRecordable.new(role: "view", depends_on_recording_id: 2),
      root_id: 10
    )

    RecordingStudio.stub(:root_recording_id_for, lambda(&:root_id)) do
      RecordingStudio::Recording.stub(:unscoped, recording_finder(manager)) do
        assert RecordingStudioAccessible::DependentAccess.effective?(access_recording)
      end
    end
  end

  def test_grant_error_rejects_missing_manager
    RecordingStudioAccessible::DependentAccess.stub(:column_available?, true) do
      RecordingStudio::Recording.stub(:unscoped, recording_finder(nil)) do
        assert_equal RecordingStudioAccessible::DependentAccess::MISSING_MANAGER_MESSAGE,
                     RecordingStudioAccessible::DependentAccess.grant_error(
                       target_recording: Recording.new(id: 1, root_id: 10),
                       role: :view,
                       depends_on: Recording.new(id: 99)
                     )
      end
    end
  end

  def test_grant_error_rejects_non_access_or_off_root_manager
    manager = Recording.new(id: 2, recordable_type: "Workspace", recordable: nil, root_id: 11)
    target = Recording.new(id: 1, root_id: 10)

    RecordingStudio.stub(:root_recording_id_for, lambda(&:root_id)) do
      RecordingStudio::Recording.stub(:unscoped, recording_finder(manager)) do
        RecordingStudioAccessible::DependentAccess.stub(:column_available?, true) do
          assert_equal RecordingStudioAccessible::DependentAccess::NOT_ACCESS_SAME_ROOT_MESSAGE,
                       RecordingStudioAccessible::DependentAccess.grant_error(
                         target_recording: target,
                         role: :view,
                         depends_on: manager
                       )
        end
      end
    end
  end

  def test_grant_error_rejects_role_that_exceeds_manager
    manager = Recording.new(
      id: 2,
      recordable_type: "RecordingStudio::Access",
      recordable: AccessRecordable.new(role: "view"),
      root_id: 10
    )
    target = Recording.new(id: 1, root_id: 10)

    RecordingStudio.stub(:root_recording_id_for, lambda(&:root_id)) do
      RecordingStudio::Recording.stub(:unscoped, recording_finder(manager)) do
        RecordingStudioAccessible::DependentAccess.stub(:column_available?, true) do
          assert_equal RecordingStudioAccessible::DependentAccess::ROLE_EXCEEDS_MESSAGE,
                       RecordingStudioAccessible::DependentAccess.grant_error(
                         target_recording: target,
                         role: :admin,
                         depends_on: manager
                       )
        end
      end
    end
  end

  def test_grant_error_rejects_self_dependency
    manager = Recording.new(
      id: 2,
      recordable_type: "RecordingStudio::Access",
      recordable: AccessRecordable.new(role: "admin"),
      root_id: 10
    )

    RecordingStudio.stub(:root_recording_id_for, lambda(&:root_id)) do
      RecordingStudio::Recording.stub(:unscoped, recording_finder(manager)) do
        RecordingStudioAccessible::DependentAccess.stub(:column_available?, true) do
          assert_equal RecordingStudioAccessible::DependentAccess::CYCLE_MESSAGE,
                       RecordingStudioAccessible::DependentAccess.grant_error(
                         target_recording: manager,
                         role: :view,
                         depends_on: manager,
                         dependent_recording: manager
                       )
        end
      end
    end
  end

  def test_grant_error_is_nil_for_a_valid_dependent_grant
    manager = Recording.new(
      id: 2,
      recordable_type: "RecordingStudio::Access",
      recordable: AccessRecordable.new(role: "admin"),
      root_id: 10
    )
    target = Recording.new(id: 1, root_id: 10)

    RecordingStudio.stub(:root_recording_id_for, lambda(&:root_id)) do
      RecordingStudio::Recording.stub(:unscoped, recording_finder(manager)) do
        RecordingStudioAccessible::DependentAccess.stub(:column_available?, true) do
          assert_nil RecordingStudioAccessible::DependentAccess.grant_error(
            target_recording: target,
            role: :edit,
            depends_on: manager
          )
        end
      end
    end
  end

  private

  def recording_finder(recording)
    finder = Object.new
    finder.define_singleton_method(:find_by) do |**|
      recording
    end
    finder
  end
end
