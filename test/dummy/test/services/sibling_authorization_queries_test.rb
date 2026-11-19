# frozen_string_literal: true

require_relative "../test_helper"

class SiblingAuthorizationQueriesTest < ActiveSupport::TestCase
  SIBLING_COUNT = 10

  setup do
    @writer = create_user("sibling-auth-writer@example.com")
    @actor = create_user("sibling-auth-actor@example.com")
    Current.actor = @writer

    workspace = Workspace.create!(name: "Sibling Auth")
    @root = create_root_recording(workspace)
    @siblings = Array.new(SIBLING_COUNT) do |index|
      folder = Folder.create!(workspace: workspace, name: "Sibling #{index}", summary: "Sibling", position: index)
      create_child_recording(recordable: folder, parent_recording: @root)
    end
    create_direct_access_recording(actor: @writer, role: :admin, parent_recording: @root)
    @actor_root_grant = create_direct_access_recording(actor: @actor, role: :view, parent_recording: @root)
  end

  teardown do
    Current.actor = nil
  end

  test "authorized? over sibling recordings does not repeat the ancestor walk" do
    recordings = @siblings.map { |recording| RecordingStudio::Recording.find(recording.id) }
    single = nil
    crowd = nil
    recursive = nil

    ActiveRecord::Base.cache do
      single = query_count { authorize(recordings.first, :view) }
      ActiveRecord::Base.connection.clear_query_cache
      statements = []
      crowd = query_count(statements) do
        recordings.each do |recording|
          assert authorize(recording, :view), "sibling #{recording.id} should inherit view"
        end
      end
      recursive = statements.count { |sql| sql.include?("WITH RECURSIVE") }
    end

    assert_equal SIBLING_COUNT, recordings.size
    assert_operator recursive, :<=, 1, "ancestor walk ran #{recursive} times for #{SIBLING_COUNT} siblings"
    assert_operator crowd, :<=, single + (2 * (SIBLING_COUNT - 1)),
                    "single=#{single} crowd=#{crowd} recursive=#{recursive}"
    assert_operator crowd, :<, single * SIBLING_COUNT,
                    "single=#{single} crowd=#{crowd}"
  end

  test "one authorization preloads every access row on the path together" do
    create_direct_access_recording(actor: @actor, role: :edit, parent_recording: @siblings.first)
    recording = RecordingStudio::Recording.find(@siblings.first.id)
    loads = []

    ActiveRecord::Base.uncached do
      query_count(loads) { assert authorize(recording, :edit) }
    end

    access_loads = loads.count { |sql| sql.include?("recording_studio_accesses") && sql.exclude?("INNER JOIN") }
    assert_operator access_loads, :<=, 1, loads.grep(/recording_studio_accesses/).join("\n")
  end

  test "ancestor walks are not reused outside a request" do
    recordings = @siblings.first(2).map { |recording| RecordingStudio::Recording.find(recording.id) }

    recursive = nil
    ActiveRecord::Base.uncached do
      statements = []
      query_count(statements) { recordings.each { |recording| authorize(recording, :view) } }
      recursive = statements.count { |sql| sql.include?("WITH RECURSIVE") }
    end

    assert_equal 2, recursive
  end

  test "nested, sibling, revoked, and inherited roles stay on the same recordings" do
    edited = @siblings.first
    plain = @siblings.second
    edit_grant = create_direct_access_recording(actor: @actor, role: :edit, parent_recording: edited)

    nested_page = Page.create!(folder: edited.recordable, title: "Nested", summary: "Nested", position: 0)
    nested = create_child_recording(recordable: nested_page, parent_recording: edited)

    assert_equal :edit, role_for(edited)
    assert_equal :edit, role_for(nested)
    assert_equal :view, role_for(plain)
    assert authorize(edited, :edit)
    assert authorize(nested, :edit)
    refute authorize(plain, :edit)

    upgraded = RecordingStudioAccessible.update_access(
      recording: @root,
      access_recording: @actor_root_grant,
      role: :admin,
      manager_actor: @writer
    )
    assert upgraded.success?, upgraded.error
    assert_equal :admin, role_for(plain)
    assert_equal :admin, role_for(edited)
    assert_equal :admin, role_for(nested)
    assert authorize(plain, :admin)

    revoked = RecordingStudioAccessible.revoke_access(
      recording: edited,
      access_recording: edit_grant,
      manager_actor: @writer
    )
    assert revoked.success?, revoked.error
    assert_equal :admin, role_for(edited)
    assert_equal :admin, role_for(plain)
    refute outsider_edit_after_trash
  end

  private

  def authorize(recording, role)
    RecordingStudioAccessible.authorized?(actor: @actor, recording: recording, role: role)
  end

  def role_for(recording)
    RecordingStudioAccessible.role_for(actor: @actor, recording: recording)
  end

  def outsider_edit_after_trash
    outsider = create_user("sibling-auth-outsider@example.com")
    grant = create_direct_access_recording(actor: outsider, role: :edit, parent_recording: @siblings.second)
    grant.update_column(:trashed_at, Time.current)
    RecordingStudioAccessible.authorized?(actor: outsider, recording: @siblings.second, role: :edit)
  end

  def query_count(log = nil)
    count = 0
    callback = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:name] == "SCHEMA" || payload[:name] == "TRANSACTION"

      count += 1
      log << payload[:sql].to_s.squish if log
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    count
  end

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end
end
