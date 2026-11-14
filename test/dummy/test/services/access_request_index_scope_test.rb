# frozen_string_literal: true

require_relative "../test_helper"

class AccessRequestIndexScopeTest < ActiveSupport::TestCase
  KIT = :"index.scope_probe"

  setup do
    @configuration = RecordingStudioAccessible.configuration
    @authorizer = @configuration.access_management_authorizer
    @audiences = @configuration.action_audiences.to_h

    @admin = create_user("scope-admin@example.com")
    @editor = create_user("scope-editor@example.com")
    @holder = create_user("scope-holder@example.com")
    @dependent = create_user("scope-dependent@example.com")
    @requester = create_user("scope-requester@example.com")
    @other_requester = create_user("scope-other-requester@example.com")

    @workspace = Workspace.create!(name: "Scope Workspace")
    @root = create_root_recording(@workspace)
    @folder = Folder.create!(workspace: @workspace, name: "Scope Folder", summary: "Folder", position: 0)
    @folder_recording = create_child_recording(recordable: @folder, parent_recording: @root)
    @other_workspace = Workspace.create!(name: "Scope Other")
    @other = create_root_recording(@other_workspace)

    @admin_grant = bootstrap(@admin, @root)
    @holder_grant = bootstrap(@holder, @other)
    grant(@editor, :edit, @root)
  end

  teardown do
    @configuration.access_management_authorizer = @authorizer
    @configuration.action_audiences.replace(@audiences)
  end

  test "pages match the policy for allow, deny, inheritance, and a relation" do
    root_request = ask(@requester, @root, "root")
    child_request = ask(@other_requester, @folder_recording, "child")
    hidden = ask(@requester, @other, "other")
    recordings = RecordingStudio::Recording.unscoped.where(id: [@root.id, @folder_recording.id, @other.id])

    assert_parity(recordings, @admin)
    assert_includes page_ids(recordings, @admin), root_request.id
    assert_includes page_ids(recordings, @admin), child_request.id
    refute_includes page_ids(recordings, @admin), hidden.id

    assert_empty page_ids(recordings, @editor)
    assert_empty page_ids(recordings, @requester)

    child_admin = create_user("scope-child-admin@example.com")
    grant(child_admin, :admin, @folder_recording)
    child_only = page_ids([@root, @folder_recording], child_admin)
    assert_equal [child_request.id], child_only
    assert_parity([@root, @folder_recording], child_admin)
  end

  test "a narrowed audience constraint does not change who sees a request" do
    request_recording = ask(@requester, @root, "audience")
    @configuration.action_audiences[KIT] = {
      allowed: %i[public signed_in granted],
      default: :public,
      granted_roles: %i[view edit admin],
      manage_role: :admin
    }
    RecordingStudioAccessible.set_audience!(recording: @root, action: KIT, audience: :public, actor: @admin)
    RecordingStudioAccessible.set_audience_constraint!(
      root: @root, action: KIT, allowed_audiences: %i[granted], actor: @admin
    )
    assert_equal :granted, RecordingStudioAccessible.effective_audience(recording: @root, action: KIT)

    assert_includes page_ids(@root, @admin), request_recording.id
    assert_empty page_ids(@root, @editor)
    assert_parity([@root, @other], @admin)
    assert_parity([@root, @other], @editor)
  end

  test "dependent grants and trashed rows match the policy across pages" do
    dependent_grant = RecordingStudioAccessible.grant_access(
      recording: @other, actor: @dependent, role: :admin, manager_actor: @holder, depends_on: @holder_grant
    )
    assert dependent_grant.success?, dependent_grant.error.to_s
    narrowed = RecordingStudioAccessible.grant_access(
      recording: @other, actor: @editor, role: :view, manager_actor: @holder, depends_on: @holder_grant
    )
    assert narrowed.success?, narrowed.error.to_s

    requests = []
    12.times do |index|
      person = create_user("scope-page-#{index}@example.com")
      recording = index.even? ? @root : @other
      request_recording = ask(person, recording, "page-#{index}")
      request_recording.update_columns(created_at: index.minutes.ago)
      requests << request_recording
    end
    requests[3].update_column(:trashed_at, Time.current)

    candidates = [@root, @other]
    assert_parity(candidates, @admin, status: "all")
    assert_parity(candidates, @dependent, status: "all")
    assert_empty page_ids(candidates, @editor, status: "all")
    walk_pages(candidates, @admin)
    walk_pages(candidates, @dependent)

    folder_request = ask(create_user("scope-folder-requester@example.com"), @folder_recording, "under trash")
    kept_grant = grant(@holder, :admin, @folder_recording)

    @holder_grant.update_column(:trashed_at, Time.current)
    assert_empty page_ids(candidates, @dependent, status: "all")
    assert_parity(candidates, @dependent, status: "all")
    assert_parity(candidates, @admin, status: "all")

    @admin_grant.update_column(:trashed_at, Time.current)
    assert_empty page_ids(candidates, @admin, status: "pending")
    assert_parity(candidates, @admin)

    @root.update_column(:trashed_at, Time.current)
    assert_includes page_ids([@folder_recording], @holder), folder_request.id
    assert_parity([@root, @folder_recording], @holder)
    kept_grant.update_column(:trashed_at, Time.current)
    assert_empty page_ids([@folder_recording], @holder)
  end

  test "a replaced authorizer is still the decision" do
    request_recording = ask(@requester, @root, "custom")
    @configuration.access_management_authorizer = ->(**) { false }
    assert_empty page_ids(@root, @admin)
    assert_parity(@root, @admin)

    @configuration.access_management_authorizer = ->(recording:, actor:, controller: nil) do
      controller == :sentinel && actor == @editor && recording.id == @root.id
    end
    assert_empty page_ids(@root, @editor, controller: :other)
    assert_includes page_ids(@root, @editor, controller: :sentinel), request_recording.id
    assert_parity(@root, @editor, controller: :sentinel)
    refute_includes page_ids(@root, @admin, controller: :sentinel), request_recording.id
  end

  test "the default authorizer does not authorize every parent" do
    parents = Array.new(24) do |index|
      workspace = Workspace.create!(name: "Scope bulk #{index}")
      root = create_root_recording(workspace)
      ask(create_user("scope-bulk-#{index}@example.com"), root, "bulk") unless index == 0
      root
    end
    parents << @root
    ask(@requester, @root, "kept")

    queries = count_queries { page_for(parents, @admin, status: nil) }
    assert_operator queries, :<, 20
    assert_operator parents.size, :>, queries
    assert_parity(parents, @admin)
  end

  private

  def bootstrap(actor, recording)
    result = RecordingStudioAccessible.bootstrap_owner_access!(recording: recording, actor: actor)
    assert result.success?, result.error.to_s
    result.value
  end

  def grant(actor, role, recording)
    result = RecordingStudioAccessible.grant_access(
      recording: recording, actor: actor, role: role, manager_actor: @admin
    )
    assert result.success?, result.error.to_s
    result.value
  end

  def ask(actor, recording, message)
    result = RecordingStudioAccessible.request_access(recording: recording, actor: actor, message: message)
    assert result.success?, result.error.to_s
    result.value
  end

  def page_ids(recordings, actor, status: nil, cursor: nil, controller: nil)
    page_for(recordings, actor, status:, cursor:, controller:).requests.map(&:id)
  end

  def page_for(recordings, actor, status:, cursor: nil, controller: nil)
    RecordingStudioAccessible::AccessRequestIndex.page(
      recordings: recordings, actor: actor, controller: controller, status: status, cursor: cursor
    )
  end

  def assert_parity(recordings, actor, status: nil, cursor: nil, controller: nil)
    page = page_for(recordings, actor, status:, cursor:, controller:)
    oracle = oracle_rows(recordings, actor, status: page.status, cursor:, controller:)
    visible = oracle.first(RecordingStudioAccessible::AccessRequestIndex::PAGE_SIZE)

    assert_equal visible.map(&:id), page.requests.map(&:id)
    assert_equal oracle.size > visible.size, page.has_more
    assert_equal(visible.last && RecordingStudioAccessible::AccessRequestIndex.cursor_for(visible.last), page.next_cursor)
    assert_equal allowed_ids(recordings, actor, controller).size > 1, page.multiple
    page.requests.each do |request|
      assert policy_allows(request.parent_recording, actor, controller)
    end
    page
  end

  def walk_pages(recordings, actor)
    cursor = nil
    seen = []
    4.times do
      page = assert_parity(recordings, actor, status: "all", cursor: cursor)
      seen.concat(page.requests.map(&:id))
      break unless page.has_more

      cursor = page.next_cursor
    end
    assert_equal seen.uniq, seen
    hidden = oracle_rows(recordings, actor, status: "all", cursor: nil, controller: nil).map(&:id)
    assert_equal hidden, seen
  end

  def oracle_rows(recordings, actor, status:, cursor:, controller:)
    scope = RecordingStudioAccessible::AccessRequestQuery.for_parents(allowed_ids(recordings, actor, controller))
    scope = scope.where(recording_studio_access_requests: { status: status }) unless status == "all"
    time_text, id = cursor.to_s.split("|", 2)
    if id.to_s.match?(/\A[0-9a-f-]{36}\z/i)
      scope = scope.where(RecordingStudioAccessible::AccessRequestIndex::CURSOR_SQL, Time.zone.parse(time_text), id)
    end
    scope.limit(RecordingStudioAccessible::AccessRequestIndex::PAGE_SIZE + 1).to_a
  end

  def allowed_ids(recordings, actor, controller)
    ids = recording_ids(recordings)
    RecordingStudio::Recording.unscoped.where(id: ids).select do |recording|
      policy_allows(recording, actor, controller)
    end.map(&:id)
  end

  def policy_allows(recording, actor, controller)
    RecordingStudioAccessible::AccessManagementPolicy.allowed?(
      recording: recording, actor: actor, controller: controller
    )
  end

  def recording_ids(recordings)
    return [] if recordings.blank?
    return [recordings.id] if recordings.is_a?(RecordingStudio::Recording)
    return recordings.pluck(:id) if recordings.respond_to?(:pluck)

    Array(recordings).map { |item| item.respond_to?(:id) ? item.id : item }
  end

  def count_queries
    count = 0
    callback = lambda do |*args|
      payload = ActiveSupport::Notifications::Event.new(*args).payload
      count += 1 unless payload[:name] == "SCHEMA" || payload[:cached]
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    count
  end

  def create_user(email)
    User.find_by(email: email) || User.create!(
      email: email, password: "Password", password_confirmation: "Password"
    )
  end
end
