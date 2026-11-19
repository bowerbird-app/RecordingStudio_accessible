# frozen_string_literal: true

require_relative "../test_helper"

class RankedCustomRolesTest < ActiveSupport::TestCase
  setup do
    @admin = create_user("ranked-roles-admin@example.com")
    @editor = create_user("ranked-roles-editor@example.com")
    @downloader = create_user("ranked-roles-downloader@example.com")
    @workspace = Workspace.create!(name: "Ranked Roles Workspace")
    @root = create_root_recording(@workspace)
    @admin_access = RecordingStudioAccessible.bootstrap_owner_access!(recording: @root, actor: @admin).value
    folder = Folder.create!(workspace: @workspace, name: "Press kit", summary: "Files", position: 0)
    @kit = create_child_recording(recordable: folder, parent_recording: @root)
    page = Page.create!(folder: folder, title: "Section", summary: "Notes", position: 0)
    @section = create_child_recording(recordable: page, parent_recording: @kit)
    Folder.accessible_roles :view, :download, :edit, :admin
  end

  teardown do
    Folder.clear_accessible_roles! if Folder.instance_variable_defined?(:@accessible_role_set)
  end

  test "download on a kit satisfies view and not edit" do
    grant(@downloader, :download, @kit)

    assert_equal :download, RecordingStudioAccessible.role_for(actor: @downloader, recording: @kit)
    assert RecordingStudioAccessible.authorized?(actor: @downloader, recording: @kit, role: :view)
    assert RecordingStudioAccessible.authorized?(actor: @downloader, recording: @kit, role: :download)
    refute RecordingStudioAccessible.authorized?(actor: @downloader, recording: @kit, role: :edit)
    refute RecordingStudioAccessible.authorized_for_role?(actor: @editor, recording: @kit, role: :download)
  end

  test "a custom role fails closed on a type that does not declare it" do
    staff = ensure_staff_admin!(@admin)
    stray = create_direct_access_recording(actor: @downloader, role: :download, parent_recording: @root)

    assert_equal "download", stray.recordable.role
    refute RecordingStudioAccessible.authorized?(actor: @admin, recording: @root, role: :download)
    refute RecordingStudioAccessible.authorized?(actor: @admin, recording: staff, role: :download)
    refute RecordingStudioAccessible.authorized?(actor: @downloader, recording: @root, role: :view)
    refute RecordingStudioAccessible.authorized?(actor: @downloader, recording: @kit, role: :download)
    assert RecordingStudioAccessible.authorized?(actor: @admin, recording: @root, role: :admin)
    assert RecordingStudioAccessible.authorized?(actor: @admin, recording: @kit, role: :admin)
    refute RecordingStudioAccessible.authorized?(actor: @admin, recording: @kit, role: :download)
  end

  test "an admin grant on the kit satisfies download and a kit download covers descendants at view" do
    grant(@admin, :admin, @kit)
    grant(@downloader, :download, @kit)

    assert RecordingStudioAccessible.authorized?(actor: @admin, recording: @kit, role: :download)
    assert RecordingStudioAccessible.authorized?(actor: @downloader, recording: @section, role: :view)
    refute RecordingStudioAccessible.authorized?(actor: @downloader, recording: @section, role: :edit)
    refute RecordingStudioAccessible.authorized?(actor: @downloader, recording: @section, role: :download)
  end

  test "role_for picks the strongest ranked ancestor and list sql matches authorized?" do
    grant(@editor, :edit, @root)
    grant(@editor, :download, @kit)

    assert_equal :edit, RecordingStudioAccessible.role_for(actor: @editor, recording: @kit)
    assert_equal :edit, RecordingStudioAccessible.role_for(actor: @editor, recording: @section)
    assert RecordingStudioAccessible.authorized?(actor: @editor, recording: @kit, role: :download)
    refute RecordingStudioAccessible.authorized_for_role?(actor: @admin, recording: @kit, role: :download)
    refute RecordingStudioAccessible.authorized?(actor: @editor, recording: @section, role: :download)

    %i[view edit download].each do |role|
      listed = RecordingStudioAccessible.authorized_recording_ids(actor: @editor, root: @root, role: role).pluck(:id)
      tree.each do |recording|
        if RecordingStudioAccessible.authorized?(actor: @editor, recording: recording, role: role)
          assert_includes listed, recording.id
        else
          refute_includes listed, recording.id
        end
      end
    end
  end

  test "actors at a custom role are included only when that role is declared and ranked high enough" do
    grant(@downloader, :download, @kit)
    grant(@editor, :edit, @kit)
    kit_admin = create_user("ranked-roles-kit-admin@example.com")
    grant(kit_admin, :admin, @kit)

    view_ids = actor_ids(@kit, :view)
    edit_ids = actor_ids(@kit, :edit)
    download_ids = actor_ids(@kit, :download)

    assert_includes view_ids, @downloader.id
    assert_includes view_ids, @editor.id
    refute_includes edit_ids, @downloader.id
    assert_includes edit_ids, @editor.id
    assert_includes download_ids, @downloader.id
    assert_includes download_ids, kit_admin.id
    refute_includes download_ids, @admin.id
    assert_empty RecordingStudioAccessible.actors_with_access(recording: @root, minimum_role: :download)
    assert_empty RecordingStudioAccessible.actors_with_access(recording: @section, minimum_role: :download)
  end

  test "an editor can grant download and cannot grant admin" do
    grant(@editor, :edit, @kit)

    assert RecordingStudioAccessible::RoleCeiling.allowed?(recording: @kit, manager: @editor, role: :download)
    refute RecordingStudioAccessible::RoleCeiling.allowed?(recording: @kit, manager: @editor, role: :admin)
    assert RecordingStudioAccessible::RoleCeiling.allowed?(recording: @kit, manager: @admin, role: :download)
  end

  test "invites and access requests accept download only on a type that declares it" do
    invited = RecordingStudioAccessible.invite_access(
      recording: @kit, email: "ranked-download-invite@example.com", role: :download, manager_actor: @admin
    )
    rejected = RecordingStudioAccessible.invite_access(
      recording: @root, email: "ranked-root-invite@example.com", role: :download, manager_actor: @admin
    )
    requested = RecordingStudioAccessible.request_access(
      recording: @kit, actor: @downloader, role: :download, message: "I need the files"
    )
    refused = RecordingStudioAccessible.request_access(
      recording: @root, actor: @downloader, role: :download, message: "I need the workspace"
    )

    assert invited.success?, invited.error
    assert rejected.failure?
    assert_equal "Role is invalid", rejected.error
    assert requested.success?, requested.error
    assert refused.failure?
    assert_equal "Role is invalid", refused.error
  end

  test "a download grant does not count as the last admin" do
    grant(@downloader, :download, @kit)

    result = RecordingStudioAccessible.update_access(
      recording: @root,
      access_recording: @admin_access,
      role: :view,
      manager_actor: @admin
    )

    assert result.failure?
    assert_equal "Add another admin before changing the last admin's role.", result.error
    assert_equal :admin, RecordingStudioAccessible.role_for(actor: @admin, recording: @root)
  end

  test "built-in roles on a type with no custom roles stay in the same order" do
    viewer = create_user("ranked-roles-viewer@example.com")
    grant(viewer, :view, @root)
    grant(@editor, :edit, @root)

    assert_equal :view, RecordingStudioAccessible.role_for(actor: viewer, recording: @root)
    assert RecordingStudioAccessible.authorized?(actor: viewer, recording: @section, role: :view)
    refute RecordingStudioAccessible.authorized?(actor: viewer, recording: @section, role: :edit)
    assert RecordingStudioAccessible.authorized?(actor: @editor, recording: @section, role: :edit)
    refute RecordingStudioAccessible.authorized?(actor: @editor, recording: @section, role: :admin)
    assert_equal %w[view edit admin], RecordingStudioAccessible.roles_for(@root)
  end

  test "query counts stay flat as the tree and the actor list grow" do
    grant(@downloader, :download, @kit)
    grant(@editor, :view, @root)
    RecordingStudioAccessible.authorized?(actor: @downloader, recording: @section, role: :view)
    RecordingStudioAccessible.authorized_recording_ids(actor: @editor, root: @root, role: :view).pluck(:id)
    RecordingStudioAccessible.actors_with_access(recording: @kit, minimum_role: :view)

    role_sql = sql_count { RecordingStudioAccessible.role_for(actor: @downloader, recording: @section) }
    allowed_sql = sql_count { RecordingStudioAccessible.authorized?(actor: @downloader, recording: @section, role: :view) }
    list_ids = nil
    list_sql = sql_count do
      list_ids = RecordingStudioAccessible.authorized_recording_ids(actor: @editor, root: @root, role: :view).pluck(:id)
    end
    actor_sql = sql_count { RecordingStudioAccessible.actors_with_access(recording: @kit, minimum_role: :view) }

    4.times do |index|
      extra = Page.create!(folder: @kit.recordable, title: "Extra #{index}", summary: "Extra", position: index + 1)
      create_child_recording(recordable: extra, parent_recording: @kit)
      person = create_user("ranked-roles-extra-#{index}@example.com")
      grant(person, :view, @kit)
    end

    assert_equal role_sql, sql_count { RecordingStudioAccessible.role_for(actor: @downloader, recording: @section) }
    assert_equal allowed_sql, sql_count {
      RecordingStudioAccessible.authorized?(actor: @downloader, recording: @section, role: :view)
    }
    grown_ids = nil
    assert_equal list_sql, sql_count {
      grown_ids = RecordingStudioAccessible.authorized_recording_ids(actor: @editor, root: @root, role: :view).pluck(:id)
    }
    assert_operator grown_ids.length, :>, list_ids.length
    assert_equal actor_sql, sql_count { RecordingStudioAccessible.actors_with_access(recording: @kit, minimum_role: :view) }
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def grant(actor, role, recording)
    create_direct_access_recording(actor: actor, role: role, parent_recording: recording)
  end

  def tree
    [@root, @kit, @section]
  end

  def actor_ids(recording, minimum_role)
    RecordingStudioAccessible.actors_with_access(recording: recording, minimum_role: minimum_role).map { |entry| entry.actor.id }
  end

  def sql_count
    ActiveRecord::Base.connection.clear_query_cache
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
      next if payload[:cached] || payload[:name] == "SCHEMA"

      count += 1
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end
