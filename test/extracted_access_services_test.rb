# frozen_string_literal: true

require "test_helper"

class ExtractedAccessServicesTest < Minitest::Test
  Recording = Struct.new(:id, :parent_recording, :recordable, :root_recording_id, keyword_init: true)
  Actor = Struct.new(:id) do
    def self.base_class
      self
    end
  end
  AccessRecordable = Struct.new(:role)
  AccessRecording = Struct.new(:parent_recording_id, :recordable)

  def test_access_path_builds_parent_chain_and_stops_cycles
    root = Recording.new(id: 1)
    child = Recording.new(id: 2, parent_recording: root)
    root.parent_recording = child

    RecordingStudio.stub(:root_recording_or_self, root) do
      path = RecordingStudio::Services::AccessPath.new(recording: child).build

      assert_equal [2, 1], path.path_recordings.map(&:id)
      assert_equal [child, root], path.lookup_recordings
      assert_same root, path.root_recording
    end
  end

  def test_access_grant_lookup_returns_first_role_by_parent_id
    actor = Actor.new(1)
    parent = Recording.new(id: 10)
    other_parent = Recording.new(id: 20)
    access_recordings = [
      AccessRecording.new(10, AccessRecordable.new("edit")),
      AccessRecording.new(10, AccessRecordable.new("admin")),
      AccessRecording.new(20, AccessRecordable.new("view"))
    ]

    RecordingStudioAccessible::DirectAccessQuery.stub(:access_recordings_for_actor_in, access_recordings) do
      lookup = RecordingStudio::Services::AccessGrantLookup.new(actor: actor, recordings: [parent, other_parent, nil])

      assert_equal "edit", lookup.role_for(parent)
      assert_equal "view", lookup.role_for(other_parent)
      assert_nil lookup.role_for(nil)
    end
  end

  def test_access_grant_lookup_returns_empty_without_actor_or_recordings
    lookup_without_actor = RecordingStudio::Services::AccessGrantLookup.new(actor: nil, recordings: [Recording.new(id: 1)])
    lookup_without_recordings = RecordingStudio::Services::AccessGrantLookup.new(actor: Actor.new(1), recordings: [])

    assert_nil lookup_without_actor.role_for(Recording.new(id: 1))
    assert_nil lookup_without_recordings.role_for(Recording.new(id: 1))
  end

  def test_access_resolver_returns_nil_without_actor_or_recording
    assert_nil RecordingStudio::Services::AccessResolver.new(actor: nil, recording: Recording.new(id: 1)).resolve_role
    assert_nil RecordingStudio::Services::AccessResolver.new(actor: Actor.new(1), recording: nil).resolve_role
  end

  def test_access_resolver_prefers_direct_role_on_path
    root = Recording.new(id: 1)
    child = Recording.new(id: 2, parent_recording: root)
    access_recordings = [
      AccessRecording.new(2, AccessRecordable.new("view")),
      AccessRecording.new(1, AccessRecordable.new("admin"))
    ]

    RecordingStudio.stub(:root_recording_or_self, root) do
      RecordingStudioAccessible::DirectAccessQuery.stub(:access_recordings_for_actor_in, access_recordings) do
        assert_equal "view", RecordingStudio::Services::AccessResolver.new(actor: Actor.new(1), recording: child).resolve_role
      end
    end
  end

  def test_access_resolver_falls_back_to_root_role
    root = Recording.new(id: 1)
    child = Recording.new(id: 2, parent_recording: root)
    access_recordings = [AccessRecording.new(1, AccessRecordable.new("admin"))]

    RecordingStudio.stub(:root_recording_or_self, root) do
      RecordingStudioAccessible::DirectAccessQuery.stub(:access_recordings_for_actor_in, access_recordings) do
        assert_equal "admin", RecordingStudio::Services::AccessResolver.new(actor: Actor.new(1), recording: child).resolve_role
      end
    end
  end
end
