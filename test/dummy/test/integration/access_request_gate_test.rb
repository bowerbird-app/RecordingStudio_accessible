# frozen_string_literal: true

require_relative "../test_helper"

class ExampleAccessRequestGate
  class << self
    attr_accessor :open, :meta, :url, :explode, :labels

    def satisfied?(**)
      raise "gate down" if explode

      !!open
    end

    def continuation_url(**)
      url
    end

    def metadata_for(**)
      raise "meta down" if meta == :raise

      meta
    end

    def metadata_labels
      labels || { "why" => "Why do you want access?" }
    end
  end
end

class AccessRequestGateTest < ActionDispatch::IntegrationTest
  setup do
    @manager = create_user("gate-manager@example.com")
    @person = create_user("gate-person@example.com")
    @workspace = Workspace.create!(name: "Gated Access Request")
    @recording = create_root_recording(@workspace)
    create_direct_access_recording(actor: @manager, role: :admin, parent_recording: @recording)
    @config = RecordingStudioAccessible.configuration
    @config.register_access_request_gate(:gate_test, ExampleAccessRequestGate)
    ExampleAccessRequestGate.open = false
    ExampleAccessRequestGate.meta = { "why" => "Embargo review" }
    ExampleAccessRequestGate.url = "/continue-gate"
    ExampleAccessRequestGate.explode = false
    ExampleAccessRequestGate.labels = { "why" => "Why do you want access?" }
    sign_in @person
  end

  teardown do
    @config.access_request_gates.delete(:gate_test)
  end

  test "a satisfied gate opens the note form" do
    ExampleAccessRequestGate.open = true

    get new_request_path(access_action: "gate_test")

    assert_response :success
    assert_match "Ask for access", response.body
    assert_match "Add a note", response.body
  end

  test "an unsatisfied gate redirects inside the modal frame and on the page" do
    get new_request_path(access_action: "gate_test", presentation: "modal"), headers: modal_headers

    assert_response :redirect
    assert_includes response.redirect_url, "/continue-gate"
    assert_includes response.redirect_url, "presentation=modal"

    get new_request_path(access_action: "gate_test")

    assert_redirected_to "/continue-gate?access_action=gate_test"
  end

  test "create checks the gate again and does not record while it is open" do
    assert_no_difference -> { RecordingStudio::AccessRequest.count } do
      post request_path, params: { access_request: { message: "Please", action: "gate_test" } }
    end

    assert_response :redirect
    assert_includes response.redirect_url, "/continue-gate"
    assert_includes response.redirect_url, "access_action=gate_test"
  end

  test "an off-host continuation is not followed" do
    ExampleAccessRequestGate.url = "https://evil.example/phish"

    get new_request_path(access_action: "gate_test")

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /We couldn't open the next step\. Try again\./
    assert_match "Ask for access", response.body
    refute_match "evil.example", response.body
    assert_equal 0, RecordingStudio::AccessRequest.count
  end

  test "an unregistered action uses the default gate and fails closed" do
    previous = @config.access_request_gates[:default]
    @config.register_access_request_gate(:default, ExampleAccessRequestGate)
    ExampleAccessRequestGate.open = false

    get new_request_path(access_action: "skip")

    assert_response :redirect
    assert_includes response.redirect_url, "/continue-gate"

    assert_no_difference -> { RecordingStudio::AccessRequest.count } do
      post request_path, params: { access_request: { message: "Please", action: "skip" } }
    end
    assert_response :redirect
    assert_includes response.redirect_url, "/continue-gate"

    result = RecordingStudioAccessible.request_access(
      recording: @recording, actor: @person, action: "skip", message: "Please"
    )
    refute result.success?
    assert_equal "We couldn't open the next step. Try again.", result.error
  ensure
    @config.access_request_gates[:default] = previous
  end

  test "a raising gate fails closed with an alert" do
    ExampleAccessRequestGate.explode = true

    assert_no_difference -> { RecordingStudio::AccessRequest.count } do
      get new_request_path(access_action: "gate_test")
    end

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /We couldn't open the next step\. Try again\./
    refute_match "continue-gate", response.location.to_s

    result = RecordingStudioAccessible.request_access(
      recording: @recording, actor: @person, action: "gate_test", message: "Please"
    )
    refute result.success?
    assert_equal "We couldn't open the next step. Try again.", result.error
  end

  test "submit and resubmit store sanitized gate answers on the snapshot history" do
    ExampleAccessRequestGate.open = true
    ExampleAccessRequestGate.meta = {
      "why" => "Embargo review",
      "Bad-Key" => { "nope" => true },
      "note" => "n" * 201
    }

    post request_path, params: { access_request: { message: "Please", action: "gate_test" } }
    request_recording = pending_request
    assert_equal({ "why" => "Embargo review" }, request_recording.recordable.gate_metadata)
    submitted = request_recording.events.reorder(occurred_at: :asc, id: :asc)
                                 .find { |event| event.action == "access_request_submitted" }
    assert_equal({ "why" => "Embargo review" }, submitted.recordable.gate_metadata)

    ExampleAccessRequestGate.meta = { "why" => "Updated reason" }
    RecordingStudioAccessible.request_access(
      recording: @recording, actor: @person, action: "gate_test", message: "Again"
    )

    request_recording.reload
    assert_equal({ "why" => "Updated reason" }, request_recording.recordable.gate_metadata)
    assert_equal({ "why" => "Embargo review" }, submitted.recordable.reload.gate_metadata)
  end

  test "a metadata exception still records the request" do
    ExampleAccessRequestGate.open = true
    ExampleAccessRequestGate.meta = :raise

    post request_path, params: { access_request: { message: "Please", action: "gate_test" } }

    assert_equal({}, pending_request.recordable.gate_metadata)
  end

  test "the gate runs after the email code and before the note" do
    skip "Recording Studio Users is required for email codes" unless defined?(::RecordingStudioUser)

    sign_out @person
    get new_request_path(access_action: "gate_test")
    assert_match "Next", response.body

    post email_path, params: { email: "gate-otp@example.com", name: "Gate User", access_action: "gate_test" }
    follow_redirect!
    assert_match "Check your email", response.body

    post verify_path, params: { code: otp_code }
    assert_response :redirect
    assert_includes response.redirect_url, "/continue-gate"
    assert_includes response.redirect_url, "access_action=gate_test"
    assert_equal 0, RecordingStudio::AccessRequest.count
  end

  test "managers see gate answers and the requester does not" do
    ExampleAccessRequestGate.open = true
    request_recording = RecordingStudioAccessible.request_access(
      recording: @recording, actor: @person, action: "gate_test", message: "Please"
    ).value

    get show_path(request_recording)
    assert_response :success
    refute_match "Why do you want access?", response.body
    refute_match "Embargo review", response.body

    sign_in @manager
    get show_path(request_recording)
    assert_match "Why do you want access?", response.body
    assert_match "Embargo review", response.body
    assert_match "Please", response.body
    assert_match "requested access to", response.body
    assert_select ".flat-pack-list-item-marker", count: 0
    assert_select "turbo-frame#access_request"

    get request_path
    assert_match "Why do you want access?", response.body
    assert_match "Embargo review", response.body
    assert_match "Please", response.body
  end

  test "the example gate asks why in a modal and on a page, then shows the answer to a manager" do
    workspace = Workspace.find_or_create_by!(name: AccessRequestReasonGate::NAME)
    recording = create_root_recording(workspace)
    create_direct_access_recording(actor: @manager, role: :admin, parent_recording: recording)

    get new_path(recording, presentation: "modal", access_action: "read"), headers: modal_headers
    assert_response :redirect
    assert_match(%r{/access_request_gate\?}, response.redirect_url)
    assert_includes response.redirect_url, "presentation=modal"
    follow_redirect!(headers: modal_headers)
    assert_gate_form(page: false)

    get new_path(recording, access_action: "read")
    follow_redirect!
    assert_gate_form(page: true)

    patch "/access_request_gate", params: {
      recording_id: recording.id, access_action: "read", why: "I cover the release"
    }
    follow_redirect!
    assert_match "Ask for access", response.body

    post recording_studio_accessible.recording_access_requests_path(recording), params: {
      access_request: { message: "Please open it", action: "read" }
    }
    request_recording = RecordingStudioAccessible::AccessRequestQuery.pending_for(
      recording: recording, actor: @person
    ).first
    assert_equal({ "why" => "I cover the release" }, request_recording.recordable.gate_metadata)

    sign_in @manager
    get recording_studio_accessible.recording_access_request_path(recording, request_recording)
    assert_match "Why do you want access?", response.body
    assert_match "I cover the release", response.body
    assert_match "Please open it", response.body
  end

  private

  def create_user(email)
    User.find_by(email: email) || User.create!(email: email, password: "Password", password_confirmation: "Password")
  end

  def new_request_path(**params)
    recording_studio_accessible.new_recording_access_request_path(@recording, **params)
  end

  def new_path(recording, **params)
    recording_studio_accessible.new_recording_access_request_path(recording, **params)
  end

  def request_path
    recording_studio_accessible.recording_access_requests_path(@recording)
  end

  def email_path
    recording_studio_accessible.email_recording_access_requests_path(@recording)
  end

  def verify_path
    recording_studio_accessible.verify_recording_access_requests_path(@recording)
  end

  def pending_request
    RecordingStudioAccessible::AccessRequestQuery.pending_for(recording: @recording, actor: @person).first
  end

  def otp_code
    intent = RecordingStudioAccessible::AccessRequestIntent.order(:created_at).last
    RecordingStudioUser.otp_message(intent.otp_challenge_id).fetch(:body)[/\d{6}/]
  end

  def show_path(request_recording)
    recording_studio_accessible.recording_access_request_path(@recording, request_recording)
  end

  def modal_headers
    { "Turbo-Frame" => "access_request" }
  end

  def assert_gate_form(page:)
    assert_response :success
    assert_match "Why do you want access?", response.body
    assert_select "textarea[name=why]"
    assert_select "turbo-frame#access_request"
    if page
      assert_match "<html", response.body
    else
      refute_match(/<html/i, response.body)
    end
  end
end
