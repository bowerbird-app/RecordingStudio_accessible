# frozen_string_literal: true

require "test_helper"

class AccessGrantsForTest < ActiveSupport::TestCase
  setup do
    @user = create_user("grants-user@example.com")
    @other = create_user("grants-other@example.com")
    @workspace_actor = Workspace.create!(name: "Grants Workspace Actor")

    workspace_a = Workspace.create!(name: "Grants Workspace A")
    @root_a = create_root_recording(workspace_a)
    @root_b = create_root_recording(Workspace.create!(name: "Grants Workspace B"))
    folder = Folder.create!(workspace: workspace_a, name: "Grants Folder", summary: "Folder", position: 0)
    @folder = create_child_recording(recordable: folder, parent_recording: @root_a)
    page = Page.create!(folder: folder, title: "Grants Page", summary: "Page", position: 0)
    @page = create_child_recording(recordable: page, parent_recording: @folder)
  end

  test "access_grants_for lists kept grants on every root and filters by role" do
    view_grant = grant(@user, :view, @root_a)
    admin_grant = grant(@user, :admin, @root_b)
    workspace_grant = grant(@workspace_actor, :edit, @root_a)
    other_grant = grant(@other, :view, @root_b)
    trashed_grant = grant(@user, :edit, @folder)
    trashed_grant.update_column(:trashed_at, Time.current)

    relation = RecordingStudioAccessible.access_grants_for(actor: @user)
    refute_predicate relation, :loaded?

    assert_equal [view_grant.id, admin_grant.id].sort, relation.pluck(:id).sort
    assert_equal [admin_grant.id], RecordingStudioAccessible.access_grants_for(actor: @user, role: :admin).pluck(:id)
    assert_equal [admin_grant.id], RecordingStudioAccessible.access_grants_for(actor: @user, role: :edit).pluck(:id)
    assert_equal [view_grant.id, admin_grant.id].sort,
                 RecordingStudioAccessible.access_grants_for(actor: @user, role: :view).pluck(:id).sort
    assert_empty RecordingStudioAccessible.access_grants_for(actor: @user, role: :nope)
    assert_empty RecordingStudioAccessible.access_grants_for(actor: nil)
    assert_empty RecordingStudioAccessible::Authorization.access_grants_for(actor: nil)

    assert_equal [workspace_grant.id],
                 RecordingStudioAccessible.access_grants_for(actor: @workspace_actor).pluck(:id)
    refute_includes RecordingStudioAccessible.access_grants_for(actor: @user).pluck(:id), other_grant.id
    refute_includes RecordingStudioAccessible.access_grants_for(actor: @user).pluck(:id), trashed_grant.id

    @root_a.update_column(:trashed_at, Time.current)
    assert_includes RecordingStudioAccessible.access_grants_for(actor: @user).pluck(:id), view_grant.id

    namespaced = RecordingStudioAccessible::Authorization.access_grants_for(actor: @user, role: :admin).pluck(:id)
    assert_equal [admin_grant.id], namespaced
  end

  test "access_grants_for resolves the actor through ActorType.for" do
    actor_class = define_actor_subclass("AccessGrantsSpecialUser")
    special = actor_class.create!(
      email: "grants-special@example.com",
      password: "Password",
      password_confirmation: "Password"
    )
    grant_recording = grant(special, :edit, @root_a)

    assert_equal "User", grant_recording.recordable.actor_type
    assert_equal RecordingStudioAccessible::ActorType.for(special), grant_recording.recordable.actor_type
    assert_equal [grant_recording.id], RecordingStudioAccessible.access_grants_for(actor: special).pluck(:id)

    RecordingStudio::Access.where(id: grant_recording.recordable_id)
                           .update_all(actor_type: "AccessGrantsSpecialUser")

    assert_empty RecordingStudioAccessible.access_grants_for(actor: special)
  ensure
    remove_actor_subclass("AccessGrantsSpecialUser")
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def grant(actor, role, parent_recording)
    create_direct_access_recording(actor: actor, role: role, parent_recording: parent_recording)
  end

  def define_actor_subclass(name)
    remove_actor_subclass(name)
    Object.const_set(name, Class.new(User))
  end

  def remove_actor_subclass(name)
    Object.send(:remove_const, name) if Object.const_defined?(name, false)
  end
end
