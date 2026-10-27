# frozen_string_literal: true

require_relative "../test_helper"

class AccessRequestIndexTest < ActionDispatch::IntegrationTest
  setup do
    ActionMailer::Base.deliveries.clear
    @manager = create_user("index-manager@example.com")
    @other_manager = create_user("index-other-manager@example.com")
    @person = create_user("index-person@example.com")
    @second_person = create_user("index-second@example.com")
    @workspace = Workspace.create!(name: "Index Workspace")
    @other_workspace = Workspace.create!(name: "Other Index Workspace")
    @recording = create_root_recording(@workspace)
    @other = create_root_recording(@other_workspace)
    create_direct_access_recording(actor: @manager, role: :admin, parent_recording: @recording)
    create_direct_access_recording(actor: @other_manager, role: :admin, parent_recording: @other)
  end

  test "pending is the default and the other statuses filter the same scope" do
    pending = ask(@person, @recording, "Please open the notes")
    approved = ask(@second_person, @recording, "I can edit this")
    RecordingStudioAccessible.approve_access_request(
      request_recording: approved, manager_actor: @manager, role: "view"
    )
    sign_in @manager

    get recording_requests_path
    assert_response :success
    assert_match @person.email, response.body
    refute_match @second_person.email, response.body
    assert_select "turbo-frame#access_requests_index"
    assert_equal [ "Name", "Status", "Actions" ], header_labels
    refute_includes header_labels, "Note"
    assert_select "a[href=?]", recording_request_path(pending), text: @person.email
    assert_review_button(pending, status: "pending")
    assert_select "a[data-turbo-frame='access_requests_index'][aria-current='page']", text: "Pending"
    assert_select "a[data-turbo-frame='access_requests_index']", text: "Approved"
    assert_select "a[data-turbo-frame='access_requests_index']", text: "Denied"
    assert_select "a[data-turbo-frame='access_requests_index']", text: "All"
    assert_select ".fp-pill-button-slots", count: 0
    assert_select "span", text: "Pending" do |badges|
      classes = badges.map { |badge| badge["class"].to_s }
      assert classes.any? { |css| css.include?("badge-primary-background-color") }
      assert classes.none? { |css| css.include?("badge-warning-background-color") }
    end
    refute_match "Taken back", response.body

    get recording_requests_path(status: "approved")
    assert_match @second_person.email, response.body
    refute_match @person.email, response.body
    assert_select "a[data-turbo-frame='access_requests_index'][aria-current='page']", text: "Approved"
    assert_select "span", text: "Approved" do |badges|
      classes = badges.map { |badge| badge["class"].to_s }
      assert classes.any? { |css| css.include?("badge-default-background-color") }
      assert classes.none? { |css| css.include?("badge-success-background-color") }
      assert classes.none? { |css| css.include?("badge-primary-background-color") }
    end
    assert_review_button(approved, status: "approved")

    get recording_requests_path(status: "all")
    assert_match @person.email, response.body
    assert_match @second_person.email, response.body

    get recording_requests_path(status: "denied")
    assert_match "Nothing matches this filter.", response.body
    refute_match @person.email, response.body

    RecordingStudioAccessible.deny_access_request(
      request_recording: pending, manager_actor: @manager, review_note: "Not now"
    )
    get recording_requests_path(status: "denied")
    assert_match @person.email, response.body
    assert_select "span", text: "Denied" do |badges|
      classes = badges.map { |badge| badge["class"].to_s }
      assert classes.any? { |css| css.include?("badge-default-background-color") }
      assert classes.none? { |css| css.include?("badge-danger-background-color") }
    end
    assert_review_button(pending, status: "denied")
  end

  test "the name column shows the profile name and falls back to the email" do
    RecordingStudioUser.record_profile!(@person, actor: @person, first_name: "Ada", last_name: "Lovelace")
    named = ask(@person, @recording, "Please open the notes")
    ask(@second_person, @recording, "No name on this account")
    sign_in @manager

    get recording_requests_path
    assert_includes header_labels, "Name"
    assert_select "a[href=?] span.font-medium", recording_request_path(named), text: "Ada Lovelace"
    assert_select "td div", text: "index-person@example.com"
    assert_select "td", text: "index-second@example.com"
    assert_select "span.font-medium", text: "index-second@example.com", count: 0
  end

  test "a recording route stays on that recording and a stranger is forbidden" do
    ask(@person, @recording, "Notes for this kit")
    ask(@second_person, @other, "Notes for the other kit")
    sign_in @manager

    get recording_requests_path
    assert_match @person.email, response.body
    refute_match @second_person.email, response.body
    refute_includes header_labels, "Recording"

    sign_in @person
    get recording_requests_path
    assert_response :forbidden
  end

  test "the collection and the embed honor the host scope and the policy" do
    previous = nil
    ask(@person, @recording, "Notes for this kit")
    ask(@second_person, @other, "Notes for the other kit")
    sign_in @manager

    get collection_path
    assert_response :success
    assert_match @person.email, response.body
    refute_match @second_person.email, response.body
    refute_includes header_labels, "Recording"

    sign_in @other_manager
    create_direct_access_recording(actor: @other_manager, role: :admin, parent_recording: @recording)
    get collection_path
    assert_match @person.email, response.body
    assert_match @second_person.email, response.body
    assert_includes header_labels, "Recording"
    assert_select "a[href=?]", "/workspaces/#{@workspace.id}", text: @workspace.name
    assert_select "a[href=?]", "/workspaces/#{@other_workspace.id}", text: @other_workspace.name

    get embed_path
    assert_match @person.email, response.body
    refute_match @second_person.email, response.body

    previous = RecordingStudioAccessible.configuration.access_request_index_recordings
    RecordingStudioAccessible.configuration.access_request_index_recordings = lambda { |actor:, controller:|
      _actor = actor
      _controller = controller
      RecordingStudio::Recording.unscoped.where(id: @other.id)
    }
    get collection_path
    assert_match @second_person.email, response.body
    refute_match @person.email, response.body
  ensure
    RecordingStudioAccessible.configuration.access_request_index_recordings = previous
  end

  test "the next page follows the cursor and leaves the first page behind" do
    sign_in @manager
    11.times do |index|
      person = create_user("index-page-#{index}@example.com")
      request_recording = ask(person, @recording, "page-note-#{index}")
      request_recording.update_columns(created_at: index.minutes.ago)
    end

    get recording_requests_path
    assert_match "index-page-0@example.com", response.body
    refute_match "index-page-10@example.com", response.body
    assert_select "[data-pagination-cursor]"
    assert_select "[data-controller='flat-pack--pagination-infinite']"
    url = css_select("[data-flat-pack--pagination-infinite-url-value]").first["data-flat-pack--pagination-infinite-url-value"]

    get url
    assert_match "index-page-10@example.com", response.body
    refute_match "index-page-0@example.com", response.body
    assert_select "table tbody tr", count: 1
    assert response.body.index("<tbody") < response.body.index("index-page-10@example.com")
  end

  test "review opens the request and a save returns to the current filter" do
    request_recording = ask(@person, @recording, "Please open the notes")
    sign_in @manager

    get recording_requests_path
    assert_select "[data-pagination-cursor]"
    get review_link(request_recording)["href"], headers: { "Turbo-Frame" => "access_request" }
    assert_select "blockquote", text: "Please open the notes"
    assert_select "button[type=submit]", text: "Approve"
    assert_select "button[type=submit]", text: "Deny"
    assert_select "[data-access-request-step=show] h1"
    assert_select "[role=tab]", text: "Approve"
    assert_select "[role=tab]", text: "Deny"
    assert_select "input[type=radio][name=role][value=view][checked]"
    assert_select "textarea[name=review_note]"
    assert_select "label", text: "Reply message (optional)"
    assert_select "input[name=return_to][value=list]"
    assert_select "input[name=list_status][value=pending]"
    assert_select "input[name=list_scope][value=recording]"
    assert_select "form[data-turbo-frame=_top]", count: 2

    post transition_path(request_recording), params: list_decision("approved", "pending", role: "view")
    assert_redirected_to recording_requests_path
    follow_redirect!
    assert_match "Request approved.", response.body
    refute_match "Please open the notes", response.body
    assert RecordingStudioAccessible.authorized?(actor: @person, recording: @recording, role: "view")

    get recording_requests_path(status: "approved")
    post transition_path(request_recording), params: list_decision("denied", "approved", review_note: "Not now")
    assert_redirected_to recording_requests_path(status: "approved")
    follow_redirect!
    assert_match "Request denied.", response.body
    refute RecordingStudioAccessible.authorized?(actor: @person, recording: @recording, role: "view")

    get recording_requests_path(status: "denied")
    assert_review_button(request_recording, status: "denied")

    post transition_path(request_recording), params: { status: "approved", role: "edit" }
    assert_redirected_to recording_request_path(request_recording)
    follow_redirect!
    assert_match "Request approved.", response.body
    assert_select "[role=tab][aria-selected=true]", text: "Approve"
    assert RecordingStudioAccessible.authorized?(actor: @person, recording: @recording, role: "edit")
  end

  test "a stranger cannot decide a request from the list" do
    request_recording = ask(@person, @recording, "Leave this pending")
    sign_in @person

    get recording_requests_path
    assert_response :forbidden

    post transition_path(request_recording), params: list_decision("approved", "pending", role: "view")
    assert_redirected_to recording_requests_path
    assert_equal "pending", request_recording.reload.recordable.status
    follow_redirect!
    assert_response :forbidden
    refute RecordingStudioAccessible.authorized?(actor: @person, recording: @recording, role: "view")
  end

  test "a decision from the collection returns to that filter" do
    request_recording = ask(@person, @recording, "Collection note")
    sign_in @manager

    get collection_path
    assert_includes review_link(request_recording)["href"], "list_scope=collection"

    post transition_path(request_recording), params: list_decision("denied", "pending", review_note: "Later", scope: "collection")
    assert_redirected_to collection_path
    follow_redirect!
    assert_match "Request denied.", response.body
    refute_match "Collection note", response.body
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def ask(actor, recording, message)
    RecordingStudioAccessible.request_access(recording: recording, actor: actor, message: message).value
  end

  def recording_requests_path(**params)
    recording_studio_accessible.recording_access_requests_path(@recording, **params)
  end

  def collection_path
    recording_studio_accessible.access_requests_path
  end

  def embed_path
    "/access_request_index_demo?recording_ids=#{@recording.id}"
  end

  def header_labels
    css_select("table thead th").map { |node| node.text.squish }
  end

  def recording_request_path(request_recording)
    recording_studio_accessible.recording_access_request_path(@recording, request_recording)
  end

  def transition_path(request_recording)
    recording_studio_accessible.transition_recording_access_request_path(@recording, request_recording)
  end

  def review_link(request_recording)
    css_select("a[data-modal-id=access-request-review]").find do |link|
      link["href"].include?(request_recording.id)
    end
  end

  def assert_review_button(request_recording, status:)
    link = review_link(request_recording)
    assert link, "missing Review link for #{request_recording.id}"
    assert_equal "Review", link.text.squish
    assert_equal "default", link["data-fp-style"]
    assert_equal "access_request", link["data-turbo-frame"]
    assert_includes link["class"], "text-xs"
    assert_includes link["href"], "presentation=modal"
    assert_includes link["href"], "return_to=list"
    assert_includes link["href"], "list_status=#{status}"
    assert_includes link["href"], "list_scope=recording"
    assert_select "#access-request-review turbo-frame#access_request", count: 1
    assert_equal 1, response.body.scan("turbo:before-cache").size
    assert_includes response.body, "[data-controller='flat-pack--modal'][id^='access-request-']"
    assert_select "[role=menuitem]", count: 0
    assert_select "button", text: "Approve", count: 0
    assert_select "button", text: "Deny", count: 0
  end

  def list_decision(status, filter, review_note: nil, scope: "recording", **extra)
    { status: status, review_note: review_note, return_to: "list", list_status: filter, list_scope: scope, **extra }
  end
end
