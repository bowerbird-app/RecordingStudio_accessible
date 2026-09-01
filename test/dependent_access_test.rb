# frozen_string_literal: true

require "test_helper"

class DependentAccessTest < Minitest::Test
  AccessRecording = Struct.new(:id, :recordable_type, :recordable, :trashed_at, :root_id, keyword_init: true)
  AccessRecordable = Struct.new(:role, :depends_on_recording_id, keyword_init: true)

  def setup
    ensure_recording_class!
  end

  def teardown
    RecordingStudio.send(:remove_const, :Recording) if @created_recording_class
  end

  def test_independent_grants_are_effective
    access_recording = AccessRecording.new(id: 1, recordable: AccessRecordable.new(role: "admin"))

    assert RecordingStudioAccessible::DependentAccess.effective?(access_recording)
  end

  def test_effective_fails_closed_for_a_nil_recording
    refute RecordingStudioAccessible::DependentAccess.effective?(nil)
  end

  def test_effective_fails_closed_when_manager_is_missing
    access_recording = AccessRecording.new(
      id: 1,
      recordable: AccessRecordable.new(role: "view", depends_on_recording_id: "missing")
    )

    RecordingStudio::Recording.stub(:unscoped, recording_finder(nil)) do
      refute RecordingStudioAccessible::DependentAccess.effective?(access_recording)
    end
  end

  def test_effective_fails_closed_when_manager_is_trashed
    manager = AccessRecording.new(
      id: 2,
      recordable_type: "RecordingStudio::Access",
      recordable: AccessRecordable.new(role: "admin"),
      trashed_at: Time.now,
      root_id: 10
    )
    access_recording = AccessRecording.new(
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
    manager = AccessRecording.new(
      id: 2,
      recordable_type: "RecordingStudio::Access",
      recordable: AccessRecordable.new(role: "view"),
      root_id: 10
    )
    access_recording = AccessRecording.new(
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
    manager = AccessRecording.new(
      id: 2,
      recordable_type: "RecordingStudio::Access",
      recordable: AccessRecordable.new(role: "edit"),
      root_id: 10
    )
    access_recording = AccessRecording.new(
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

  def test_effective_fails_closed_on_a_manager_cycle
    manager = AccessRecording.new(
      id: 2,
      recordable_type: "RecordingStudio::Access",
      recordable: AccessRecordable.new(role: "admin", depends_on_recording_id: 1),
      root_id: 10
    )
    access_recording = AccessRecording.new(
      id: 1,
      recordable_type: "RecordingStudio::Access",
      recordable: AccessRecordable.new(role: "view", depends_on_recording_id: 2),
      root_id: 10
    )

    RecordingStudio.stub(:root_recording_id_for, lambda(&:root_id)) do
      RecordingStudio::Recording.stub(:unscoped, recordings_finder(1 => access_recording, 2 => manager)) do
        refute RecordingStudioAccessible::DependentAccess.effective?(access_recording)
      end
    end
  end

  def test_effective_fails_closed_when_root_lookup_raises
    manager = AccessRecording.new(
      id: 2,
      recordable_type: "RecordingStudio::Access",
      recordable: AccessRecordable.new(role: "admin"),
      root_id: 10
    )
    access_recording = AccessRecording.new(
      id: 1,
      recordable: AccessRecordable.new(role: "view", depends_on_recording_id: 2),
      root_id: 10
    )

    RecordingStudio.stub(:root_recording_id_for, ->(*) { raise "root lookup failed" }) do
      RecordingStudio::Recording.stub(:unscoped, recording_finder(manager)) do
        refute RecordingStudioAccessible::DependentAccess.effective?(access_recording)
      end
    end
  end

  def test_grant_error_is_nil_when_depends_on_is_omitted
    assert_nil RecordingStudioAccessible::DependentAccess.grant_error(
      target_recording: AccessRecording.new(id: 1),
      role: :view,
      depends_on: nil
    )
  end

  def test_grant_error_requires_the_depends_on_column
    RecordingStudioAccessible::DependentAccess.stub(:column_available?, false) do
      assert_equal RecordingStudioAccessible::DependentAccess::MISSING_COLUMN_MESSAGE,
                   RecordingStudioAccessible::DependentAccess.grant_error(
                     target_recording: AccessRecording.new(id: 1),
                     role: :view,
                     depends_on: AccessRecording.new(id: 2)
                   )
    end
  end

  def test_grant_error_rejects_missing_manager
    RecordingStudioAccessible::DependentAccess.stub(:column_available?, true) do
      RecordingStudio::Recording.stub(:unscoped, recording_finder(nil)) do
        assert_equal RecordingStudioAccessible::DependentAccess::MISSING_MANAGER_MESSAGE,
                     RecordingStudioAccessible::DependentAccess.grant_error(
                       target_recording: AccessRecording.new(id: 1, root_id: 10),
                       role: :view,
                       depends_on: AccessRecording.new(id: 99)
                     )
      end
    end
  end

  def test_grant_error_rejects_non_access_or_off_root_manager
    manager = AccessRecording.new(id: 2, recordable_type: "Workspace", recordable: nil, root_id: 11)
    target = AccessRecording.new(id: 1, root_id: 10)

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
    manager = AccessRecording.new(
      id: 2,
      recordable_type: "RecordingStudio::Access",
      recordable: AccessRecordable.new(role: "view"),
      root_id: 10
    )
    target = AccessRecording.new(id: 1, root_id: 10)

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
    manager = AccessRecording.new(
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

  def test_grant_error_rejects_a_trashed_manager
    manager = AccessRecording.new(
      id: 2,
      recordable_type: "RecordingStudio::Access",
      recordable: AccessRecordable.new(role: "admin"),
      trashed_at: Time.now,
      root_id: 10
    )

    RecordingStudioAccessible::DependentAccess.stub(:column_available?, true) do
      RecordingStudio::Recording.stub(:unscoped, recording_finder(manager)) do
        assert_equal RecordingStudioAccessible::DependentAccess::MISSING_MANAGER_MESSAGE,
                     RecordingStudioAccessible::DependentAccess.grant_error(
                       target_recording: AccessRecording.new(id: 1, root_id: 10),
                       role: :view,
                       depends_on: manager
                     )
      end
    end
  end

  def test_grant_error_rejects_a_transitive_cycle
    manager = AccessRecording.new(
      id: 2,
      recordable_type: "RecordingStudio::Access",
      recordable: AccessRecordable.new(role: "admin", depends_on_recording_id: 3),
      root_id: 10
    )
    intermediary = AccessRecording.new(
      id: 3,
      recordable_type: "RecordingStudio::Access",
      recordable: AccessRecordable.new(role: "admin", depends_on_recording_id: 1),
      root_id: 10
    )
    dependent = AccessRecording.new(
      id: 1,
      recordable_type: "RecordingStudio::Access",
      recordable: AccessRecordable.new(role: "view"),
      root_id: 10
    )

    RecordingStudio.stub(:root_recording_id_for, lambda(&:root_id)) do
      RecordingStudio::Recording.stub(:unscoped, recordings_finder(1 => dependent, 2 => manager, 3 => intermediary)) do
        RecordingStudioAccessible::DependentAccess.stub(:column_available?, true) do
          assert_equal RecordingStudioAccessible::DependentAccess::CYCLE_MESSAGE,
                       RecordingStudioAccessible::DependentAccess.grant_error(
                         target_recording: dependent,
                         role: :view,
                         depends_on: manager,
                         dependent_recording: dependent
                       )
        end
      end
    end
  end

  def test_grant_error_is_nil_for_a_valid_dependent_grant
    manager = AccessRecording.new(
      id: 2,
      recordable_type: "RecordingStudio::Access",
      recordable: AccessRecordable.new(role: "admin"),
      root_id: 10
    )
    target = AccessRecording.new(id: 1, root_id: 10)

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

  def test_manager_recording_for_returns_nil_without_a_dependency
    access_recording = AccessRecording.new(id: 1, recordable: AccessRecordable.new(role: "admin"))

    assert_nil RecordingStudioAccessible::DependentAccess.manager_recording_for(access_recording)
  end

  def test_manager_recording_for_finds_the_manager_recording
    manager = AccessRecording.new(id: 2)
    access_recording = AccessRecording.new(
      id: 1,
      recordable: AccessRecordable.new(role: "view", depends_on_recording_id: 2)
    )

    RecordingStudio::Recording.stub(:unscoped, recording_finder(manager)) do
      assert_equal manager, RecordingStudioAccessible::DependentAccess.manager_recording_for(access_recording)
    end
  end

  def test_column_available_is_false_when_access_omits_the_column
    with_access_class(Class.new { def self.column_names = ["role"] }) do
      refute RecordingStudioAccessible::DependentAccess.column_available?
    end
  end

  def test_column_available_is_true_when_access_has_the_column
    with_access_class(Class.new { def self.column_names = ["depends_on_recording_id"] }) do
      assert RecordingStudioAccessible::DependentAccess.column_available?
    end
  end

  def test_column_available_is_false_when_column_lookup_raises
    with_access_class(Class.new { def self.column_names = raise("boom") }) do
      refute RecordingStudioAccessible::DependentAccess.column_available?
    end
  end

  def test_find_recording_fails_closed_when_lookup_raises
    access_recording = AccessRecording.new(
      id: 1,
      recordable: AccessRecordable.new(role: "view", depends_on_recording_id: 2)
    )
    finder = Object.new
    finder.define_singleton_method(:find_by) { |**| raise "lookup failed" }

    RecordingStudio::Recording.stub(:unscoped, finder) do
      refute RecordingStudioAccessible::DependentAccess.effective?(access_recording)
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

  def recordings_finder(by_id)
    finder = Object.new
    finder.define_singleton_method(:find_by) do |**kwargs|
      by_id[kwargs[:id] || kwargs["id"]]
    end
    finder
  end

  def with_access_class(klass)
    original = RecordingStudio.const_defined?(:Access, false) ? RecordingStudio::Access : nil
    RecordingStudio.send(:remove_const, :Access) if original
    RecordingStudio.const_set(:Access, klass)
    yield
  ensure
    RecordingStudio.send(:remove_const, :Access) if RecordingStudio.const_defined?(:Access, false)
    RecordingStudio.const_set(:Access, original) if original
  end

  def ensure_recording_class!
    return if RecordingStudio.const_defined?(:Recording, false)

    @created_recording_class = true
    RecordingStudio.const_set(:Recording, Class.new do
      def self.unscoped = self
      def self.find_by(*) = nil

      def self.transaction
        yield
      end
    end)
  end
end
