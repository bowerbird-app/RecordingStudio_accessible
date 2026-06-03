require_relative "../test_helper"

class RecordableDeclarationsTest < ActiveSupport::TestCase
  test "dummy app declarations are valid for RecordingStudio 2" do
    assert RecordingStudio.validate_recordable_declarations!
  end

  test "dummy app recordables declare root and parent rules" do
    assert RecordingStudio.root_allowed?(Workspace)
    refute RecordingStudio.root_allowed?(Folder)
    refute RecordingStudio.root_allowed?(Page)
    refute RecordingStudio.root_allowed?(Card)

    assert_equal ["Workspace"], RecordingStudio.allowed_parent_types_for(Folder)
    assert_equal ["Folder"], RecordingStudio.allowed_parent_types_for(Page)
    assert_equal ["Page"], RecordingStudio.allowed_parent_types_for(Card)
  end

  test "access declaration is child-only and follows accessible child opt ins" do
    refute RecordingStudio.root_allowed?(RecordingStudio::Access)
    assert_equal ["Folder", "Workspace"], RecordingStudio.allowed_parent_types_for(RecordingStudio::Access)
  end
end
