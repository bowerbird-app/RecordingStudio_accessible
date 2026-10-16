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
    assert_match "Please open the notes", response.body
    refute_match "I can edit this", response.body
    assert_select "turbo-frame#access_requests_index"
    assert_equal [ "Who", "Note", "Status", "Actions" ], header_labels
    assert_select "span.truncate[title='Please open the notes']"
    assert_select "[aria-label='Request actions']"
    assert_select "[role=menuitem]", text: "View"
    assert_select "[role=menuitem]", text: "Approve as View"
    assert_select "[role=menuitem]", text: "Deny"
    refute_match "Taken back", response.body

    get recording_requests_path(status: "approved")
    assert_match "I can edit this", response.body
    refute_match "Please open the notes", response.body
    assert_select "[role=menuitem]", text: "Pending"
    assert_select "[role=menuitem]", text: "Deny"
    assert_select "[role=menuitem]", text: "Approve as View", count: 0

    get recording_requests_path(status: "all")
    assert_match "Please open the notes", response.body
    assert_match "I can edit this", response.body

    get recording_requests_path(status: "denied")
    assert_match "Nothing matches this filter.", response.body
    refute_match "Please open the notes", response.body

    RecordingStudioAccessible.deny_access_request(
      request_recording: pending, manager_actor: @manager, review_note: "Not now"
    )
    get recording_requests_path(status: "denied")
    assert_match "Please open the notes", response.body
    assert_select "[role=menuitem]", text: "Pending"
    assert_select "[role=menuitem]", text: "Approve as Edit"
  end

  test "a recording route stays on that recording and a stranger is forbidden" do
    ask(@person, @recording, "Notes for this kit")
    ask(@second_person, @other, "Notes for the other kit")
    sign_in @manager

    get recording_requests_path
    assert_match "Notes for this kit", response.body
    refute_match "Notes for the other kit", response.body
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
    assert_match "Notes for this kit", response.body
    refute_match "Notes for the other kit", response.body
    refute_includes header_labels, "Recording"

    sign_in @other_manager
    create_direct_access_recording(actor: @other_manager, role: :admin, parent_recording: @recording)
    get collection_path
    assert_match "Notes for this kit", response.body
    assert_match "Notes for the other kit", response.body
    assert_includes header_labels, "Recording"
    assert_select "a[href=?]", "/workspaces/#{@workspace.id}", text: @workspace.name
    assert_select "a[href=?]", "/workspaces/#{@other_workspace.id}", text: @other_workspace.name

    get embed_path
    assert_match "Notes for this kit", response.body
    refute_match "Notes for the other kit", response.body

    previous = RecordingStudioAccessible.configuration.access_request_index_recordings
    RecordingStudioAccessible.configuration.access_request_index_recordings = lambda { |actor:, controller:|
      _actor = actor
      _controller = controller
      RecordingStudio::Recording.unscoped.where(id: @other.id)
    }
    get collection_path
    assert_match "Notes for the other kit", response.body
    refute_match "Notes for this kit", response.body
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
    assert_match "page-note-0", response.body
    refute_match "page-note-10", response.body
    assert_select "[data-controller='flat-pack--pagination-infinite']"
    url = css_select("[data-flat-pack--pagination-infinite-url-value]").first["data-flat-pack--pagination-infinite-url-value"]

    get url
    assert_match "page-note-10", response.body
    refute_match "page-note-0", response.body
    assert_select "table tbody tr", count: 1
    assert response.body.index("<tbody") < response.body.index("page-note-10")
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
end
