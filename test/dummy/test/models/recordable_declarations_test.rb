require_relative "../test_helper"

class RecordableDeclarationsTest < ActiveSupport::TestCase
  test "dummy app declarations are valid for RecordingStudio 3" do
    assert RecordingStudio.validate_recordable_declarations!
  end

  test "dummy app recordables declare root and parent rules" do
    assert RecordingStudio.root_allowed?(MessageRoot)
    assert RecordingStudio.root_allowed?(Workspace)
    refute RecordingStudio.root_allowed?(Folder)
    refute RecordingStudio.root_allowed?(MessageGroup)
    refute RecordingStudio.root_allowed?(Page)
    refute RecordingStudio.root_allowed?(Card)

    assert_equal [ "MessageRoot" ], RecordingStudio.allowed_parent_types_for(MessageGroup)
    assert_equal [ "Workspace" ], RecordingStudio.allowed_parent_types_for(Folder)
    assert_equal [ "Folder" ], RecordingStudio.allowed_parent_types_for(Page)
    assert_equal [ "Page" ], RecordingStudio.allowed_parent_types_for(Card)
  end

  test "access declaration is child-only and follows accessible child opt ins" do
    assert_includes RecordingStudio.configuration.recordable_types, "RecordingStudio::Access"
    refute RecordingStudio.root_allowed?(RecordingStudio::Access)
    assert_equal [], RecordingStudio.declared_allowed_parent_types_for(RecordingStudio::Access)
    assert_equal [ "RecordingStudio::Access" ], RecordingStudio.capability_child_recordables_for(:accessible)
    assert_equal [ "Folder", "MessageGroup", "MessageRoot", "Workspace" ], RecordingStudio.capability_allowed_parent_types_for(RecordingStudio::Access)
    assert_equal [ "Folder", "MessageGroup", "MessageRoot", "Workspace" ], RecordingStudio.allowed_parent_types_for(RecordingStudio::Access)
    assert_equal [ "Folder", "MessageGroup", "MessageRoot", "Workspace" ],
                 RecordingStudio.recordable_parent_allowances_for(RecordingStudio::Access)
                                .fetch("recording_studio_accessible")
    assert_equal [ "RecordingStudio::Access" ], RecordingStudio.child_recordable_types_for(Workspace)
    assert_equal [ "RecordingStudio::Access" ], RecordingStudio.child_recordable_types_for(Folder)
    assert_equal [ "RecordingStudio::Access" ], RecordingStudio.child_recordable_types_for(MessageRoot)
    assert_equal [ "RecordingStudio::Access" ], RecordingStudio.child_recordable_types_for(MessageGroup)
    assert_empty RecordingStudio.child_recordable_types_for(Page)
    assert_empty RecordingStudio.child_recordable_types_for(Card)
  end
end
