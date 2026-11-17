# frozen_string_literal: true

require_relative "../test_helper"

class RoleForDepthTest < ActiveSupport::TestCase
  DEPTH = 80

  setup do
    @writer = create_user("role-for-depth-writer@example.com")
    @root_actor = create_user("role-for-depth-root@example.com")
    @subtree_actor = create_user("role-for-depth-subtree@example.com")
    Current.actor = @writer

    workspace = Workspace.create!(name: "Role For Depth")
    @root = create_root_recording(workspace)
    folder = Folder.create!(workspace: workspace, name: "Shallow", summary: "Shallow", position: 0)
    @shallow = create_child_recording(recordable: folder, parent_recording: @root)
    @deep = RecordingStudio::Recording.find(insert_chain(folder))

    create_direct_access_recording(actor: @root_actor, role: :admin, parent_recording: @root)
    create_direct_access_recording(actor: @subtree_actor, role: :edit, parent_recording: @shallow)
  end

  test "role_for at depth 80 uses a constant number of queries and the same role" do
    assert_equal 1, @shallow.ancestors.size
    assert_equal DEPTH, @deep.ancestors.size

    path = RecordingStudio::Services::AccessPath.new(recording: fresh(@deep.id)).build
    assert_equal [@deep.id, @root.id], [path.path_recordings.first.id, path.path_recordings.last.id]
    assert_equal DEPTH + 1, path.path_recordings.size
    path.path_recordings.each_cons(2) do |child, parent|
      assert_equal parent.id, child.parent_recording_id
    end

    assert_equal :admin, RecordingStudioAccessible.role_for(actor: @root_actor, recording: fresh(@shallow.id))
    assert_equal :admin, RecordingStudioAccessible.role_for(actor: @root_actor, recording: fresh(@deep.id))
    assert_equal :edit, RecordingStudioAccessible.role_for(actor: @subtree_actor, recording: fresh(@shallow.id))
    assert_equal :edit, RecordingStudioAccessible.role_for(actor: @subtree_actor, recording: fresh(@deep.id))

    assert_equal role_queries(@root_actor, @shallow.id), role_queries(@root_actor, @deep.id)
    assert_equal role_queries(@subtree_actor, @shallow.id), role_queries(@subtree_actor, @deep.id)
  end

  private

  def insert_chain(folder)
    parent = @shallow
    leaf_id = nil
    (DEPTH - 1).times do
      leaf_id = insert_child(parent: parent, recordable_id: folder.id)
      parent = RecordingStudio::Recording.find(leaf_id)
    end
    leaf_id
  end

  def insert_child(parent:, recordable_id:)
    connection = ActiveRecord::Base.connection
    now = Time.current
    id = SecureRandom.uuid
    connection.exec_insert(<<~SQL.squish, "SQL", [])
      INSERT INTO recording_studio_recordings
        (id, recordable_type, recordable_id, parent_recording_id, root_recording_id, created_at, updated_at)
      VALUES
        (#{connection.quote(id)}, 'Folder', #{connection.quote(recordable_id)},
         #{connection.quote(parent.id)}, #{connection.quote(@root.id)},
         #{connection.quote(now)}, #{connection.quote(now)})
    SQL
    id
  end

  def fresh(id)
    RecordingStudio::Recording.find(id)
  end

  def role_queries(actor, id)
    recording = fresh(id)
    query_count { RecordingStudioAccessible.role_for(actor: actor, recording: recording) }
  end

  def query_count
    ActiveRecord::Base.connection.clear_query_cache
    count = 0
    callback = lambda do |*args|
      payload = ActiveSupport::Notifications::Event.new(*args).payload
      next if payload[:cached] || payload[:name] == "SCHEMA"

      count += 1
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      ActiveRecord::Base.uncached { yield }
    end
    count
  end

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end
end
