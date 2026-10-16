# frozen_string_literal: true

require_relative "../test_helper"

class AccessRequestsTest < ActionDispatch::IntegrationTest
  setup do
    ActionMailer::Base.deliveries.clear
    Rails.cache.clear
    @manager = create_user("request-flow-manager@example.com")
    @person = create_user("request-flow-person@example.com")
    @workspace = Workspace.create!(name: "Access Request Flow")
    @recording = create_root_recording(@workspace)
    create_direct_access_recording(actor: @manager, role: :admin, parent_recording: @recording)
  end

  test "signed in visitor submits from the page and from the modal frame" do
    sign_in @person

    get new_request_path
    assert_response :success
    assert_match "Ask for access", response.body
    assert_match "Add a note", response.body
    refute_role_picker
    refute_recording_subtitle
    assert_match "<html", response.body

    post request_path, params: { access_request: { message: "From the page", action: "read" } }
    follow_redirect!
    assert_match "Request sent", response.body
    refute_recording_subtitle

    get new_request_path(presentation: "modal"), headers: modal_headers
    assert_response :success
    assert_select "turbo-frame#access_request"
    refute_recording_subtitle
    refute_match(/<html/i, response.body)
  end

  test "visitor verifies an email code then sends a request" do
    skip "Recording Studio Users is required for email codes" unless defined?(::RecordingStudioUser)

    get new_request_path
    assert_email_step

    post email_path, params: {
      email: "new-requester@example.com", name: "Ada Lovelace", role: "view", access_action: "read"
    }
    follow_redirect!
    assert_match "Check your email", response.body
    refute_recording_subtitle
    get verify_path(presentation: "modal"), headers: modal_headers
    assert_match "Check your email", response.body
    refute_recording_subtitle

    post verify_path, params: { code: otp_code }
    follow_redirect!
    assert_match "Ask for access", response.body
    assert_match "Add a note", response.body
    refute_role_picker
    refute_recording_subtitle
    get new_request_path(presentation: "modal"), headers: modal_headers
    assert_match "Ask for access", response.body
    refute_role_picker
    refute_recording_subtitle

    requester = User.find_by!(email: "new-requester@example.com")
    assert_equal "Ada Lovelace", RecordingStudioUser.display_name_for(requester)

    post request_path, params: { access_request: { message: "Hello from the visitor", action: "read" } }
    follow_redirect!
    assert_match "Request sent", response.body
    refute_recording_subtitle
    get sent_path(presentation: "modal"), headers: modal_headers
    assert_match "Request sent", response.body
    refute_recording_subtitle
    assert_equal 1, RecordingStudio::AccessRequest.where(status: "pending").count

    sign_in @manager
    get requests_path
    assert_match "Ada Lovelace", response.body
    assert_match "Hello from the visitor", response.body
    assert_match "Not chosen yet", response.body
  end

  test "visitor copy overrides follow every step" do
    get new_request_path(copy: { email_title: "Request early access", verify_title: "Early code" }, copy_scope: "")
    assert_select "h1", text: "Request early access"

    post email_path, params: {
      email: "early-access@example.com", name: "Early User",
      copy: { verify_title: "Early code" }, copy_scope: ""
    }
    follow_redirect!
    assert_select "h1", text: "Early code"
    refute_match "Check your email", response.body

    get new_request_path(copy_scope: "early_access_demo")
    assert_select "h1", text: "Request early access"
  end

  test "email step keeps a blank name when the account does not require one" do
    skip "Recording Studio Users is required for email codes" unless defined?(::RecordingStudioUser)

    refute RecordingStudioAccessible::AccessRequestIntake.name_required?

    post email_path, params: { email: "blank-name@example.com", name: "", role: "view", access_action: "read" }
    follow_redirect!
    assert_match "Check your email", response.body
    refute_recording_subtitle
    assert_nil RecordingStudioAccessible::AccessRequestIntent.order(:created_at).last.submitted_name
  end

  test "email step rejects a name that is too long" do
    skip "Recording Studio Users is required for email codes" unless defined?(::RecordingStudioUser)

    post email_path, params: { email: "long-name@example.com", name: "A" * 121, role: "view" }
    assert_response :unprocessable_entity
    assert_match "Name is too long", response.body
  end

  test "email step inside a modal frame has no document layout" do
    get new_request_path(presentation: "modal"), headers: { "Turbo-Frame" => "access_request" }

    assert_response :success
    assert_select "turbo-frame#access_request"
    assert_email_step
    refute_match(/<html/i, response.body)
  end

  test "manager reviews and approves a request" do
    request_recording = RecordingStudioAccessible.request_access(
      recording: @recording, actor: @person, role: "edit", message: "I edit"
    ).value
    sign_in @manager

    get requests_path
    assert_response :success
    assert_match @person.email, response.body
    assert_match "Pending", response.body
    assert_access_request_table("I edit")

    get request_show_path(request_recording)
    assert_match "Asked for access", response.body
    assert_match "I edit", response.body
    assert_match "Note", response.body
    assert_select "select[name=role]"

    post approve_path(request_recording), params: { role: "edit" }
    follow_redirect!
    assert_match "Approved", response.body
    assert_match "What happened", response.body
    assert RecordingStudioAccessible.authorized?(actor: @person, recording: @recording, role: "edit")
  end

  test "locked screen helper renders a modal and a page link" do
    get access_request_demo_path(recording_id: @recording.id)

    assert_response :success
    assert_match "Request access", response.body
    assert_match "Request early access", response.body
    assert_select "h2", text: "Request access", count: 0
    assert_match "data-modal-id", response.body
    assert_match "access_request", response.body
    assert_match "presentation=modal", response.body
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def new_request_path(**params)
    recording_studio_accessible.new_recording_access_request_path(@recording, **params)
  end

  def request_path
    recording_studio_accessible.recording_access_requests_path(@recording)
  end

  def requests_path
    request_path
  end

  def email_path
    recording_studio_accessible.email_recording_access_requests_path(@recording)
  end

  def verify_path(**params)
    recording_studio_accessible.verify_recording_access_requests_path(@recording, **params)
  end

  def sent_path(**params)
    recording_studio_accessible.sent_recording_access_requests_path(@recording, **params)
  end

  def modal_headers
    { "Turbo-Frame" => "access_request" }
  end

  def assert_access_request_table(note)
    headers = css_select("table thead th").map { |node| node.text.squish }
    assert_equal [ "Who", "Role", "Note", "Status", "Actions" ], headers
    assert_select "table tbody tr", count: 1
    assert_select "table tbody td", text: note
    assert response.body.index("<thead") < response.body.index("<tbody")
    assert response.body.index("<tbody") < response.body.index(note)
    assert response.body.index(note) < response.body.index("</tbody>")
  end

  def refute_recording_subtitle
    refute_match @workspace.name, response.body
  end

  def refute_role_picker
    assert_select "input[type=radio][name='access_request[role]']", count: 0
    refute_match "What do you need?", response.body
  end

  def request_show_path(request_recording)
    recording_studio_accessible.recording_access_request_path(@recording, request_recording)
  end

  def approve_path(request_recording)
    recording_studio_accessible.approve_recording_access_request_path(@recording, request_recording)
  end

  def assert_email_step
    assert_match "Request access", response.body
    assert_match @workspace.name, response.body
    assert_match "Next", response.body
    assert_select "input[name=name]"
    assert_select "input[name=name][required]", count: 0
    assert_select "h1", text: "Request access"
    assert_select "h2", text: "Request access", count: 0
    refute_match "Tell us where to send the code", response.body
    refute_match "Send code", response.body
  end

  def otp_code
    intent = RecordingStudioAccessible::AccessRequestIntent.order(:created_at).last
    RecordingStudioUser.otp_message(intent.otp_challenge_id).fetch(:body)[/\d{6}/]
  end
end
