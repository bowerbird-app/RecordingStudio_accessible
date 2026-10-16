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
    assert_match "<html", response.body

    post request_path, params: { access_request: { role: "view", message: "From the page", action: "read" } }
    follow_redirect!
    assert_match "Request sent", response.body

    get new_request_path(presentation: "modal"), headers: { "Turbo-Frame" => "access_request" }
    assert_response :success
    assert_select "turbo-frame#access_request"
    refute_match(/<html/i, response.body)
  end

  test "visitor verifies an email code then sends a request" do
    skip "Recording Studio Users is required for email codes" unless defined?(::RecordingStudioUser)

    get new_request_path
    assert_match "Tell us where to send the code", response.body

    post email_path, params: { email: "new-requester@example.com", role: "view", access_action: "read" }
    follow_redirect!
    assert_match "Check your email", response.body

    post verify_path, params: { code: otp_code }
    follow_redirect!
    assert_match "Ask for access", response.body
    assert_match "read", response.body

    post request_path, params: { access_request: { role: "view", message: "Hello", action: "read" } }
    follow_redirect!
    assert_match "Request sent", response.body
    assert_equal 1, RecordingStudio::AccessRequest.where(status: "pending").count
  end

  test "email step inside a modal frame has no document layout" do
    get new_request_path(presentation: "modal"), headers: { "Turbo-Frame" => "access_request" }

    assert_response :success
    assert_select "turbo-frame#access_request"
    assert_match "Tell us where to send the code", response.body
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

    get request_show_path(request_recording)
    assert_match "Asked for access", response.body

    post approve_path(request_recording)
    follow_redirect!
    assert_match "Approved", response.body
    assert_match "What happened", response.body
    assert RecordingStudioAccessible.authorized?(actor: @person, recording: @recording, role: "edit")
  end

  test "locked screen helper renders a modal and a page link" do
    get access_request_demo_path(recording_id: @recording.id)

    assert_response :success
    assert_match "Request access", response.body
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

  def verify_path
    recording_studio_accessible.verify_recording_access_requests_path(@recording)
  end

  def request_show_path(request_recording)
    recording_studio_accessible.recording_access_request_path(@recording, request_recording)
  end

  def approve_path(request_recording)
    recording_studio_accessible.approve_recording_access_request_path(@recording, request_recording)
  end

  def otp_code
    intent = RecordingStudioAccessible::AccessRequestIntent.order(:created_at).last
    RecordingStudioUser.otp_message(intent.otp_challenge_id).fetch(:body)[/\d{6}/]
  end
end
