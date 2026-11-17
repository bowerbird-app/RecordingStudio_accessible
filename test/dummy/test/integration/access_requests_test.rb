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
    assert_access_request_screen("form", page: true)
    assert_select "[data-access-request-step=form] form .pt-6 button[type=submit]", text: "Send request"

    post request_path, params: { access_request: { message: "From the page", action: "read" } }
    follow_redirect!
    assert_match "Request sent", response.body
    refute_recording_subtitle
    assert_access_request_screen("sent", page: true)

    get new_request_path(presentation: "modal"), headers: modal_headers
    assert_response :success
    refute_recording_subtitle
    assert_access_request_screen("form", page: false)
  end

  test "a signed-out visitor is sent to sign in and returns to the request form" do
    path = new_request_path(role: "view", access_action: "read")

    get path

    assert_redirected_to "/users/sign_in"
    assert_equal path, session["user_return_to"]

    post "/users/sign_in", params: { user: { email: @person.email, password: "Password" } }
    assert_redirected_to path

    follow_redirect!
    assert_response :success
    assert_match "Ask for access", response.body
    assert_match "Add a note", response.body
    refute_role_picker
    assert_access_request_screen("form", page: true)

    assert_difference -> { RecordingStudio::AccessRequest.count }, 1 do
      post request_path, params: { access_request: { message: "After sign in", role: "view", action: "read" } }
    end
    follow_redirect!
    assert_match "Request sent", response.body
    assert_equal 1, RecordingStudio::AccessRequest.where(status: "pending").count
  end

  test "a signed-out visitor is unauthorized when the host has no sign-in path" do
    controller = RecordingStudioAccessible::AccessRequestsController
    original = controller.instance_method(:local_sign_in_path)
    controller.define_method(:local_sign_in_path) { nil }

    get new_request_path
    assert_response :unauthorized

    assert_no_difference -> { RecordingStudio::AccessRequest.count } do
      post request_path, params: { access_request: { message: "No account" } }
    end
    assert_response :unauthorized
  ensure
    controller.define_method(:local_sign_in_path, original)
    controller.send(:private, :local_sign_in_path)
  end

  test "a signed-out create is sent to sign in and records nothing" do
    assert_no_difference -> { RecordingStudio::AccessRequest.count } do
      post request_path, params: {
        role: "view", access_action: "read", access_request: { message: "Not yet" }
      }
    end

    assert_redirected_to "/users/sign_in"
    assert_equal new_request_path(role: "view", access_action: "read"), session["user_return_to"]
  end

  test "visitor copy overrides follow the request form" do
    sign_in @person

    get new_request_path(copy: { form_title: "Ask for early access" }, copy_scope: "")
    assert_match "Ask for early access", response.body

    get new_request_path(copy_scope: "early_access_demo")
    assert_match "Ask for early access", response.body
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
    assert_access_request_table

    get request_show_path(request_recording)
    requested_on = "Requested #{I18n.l(request_recording.created_at.to_date, format: :long)}"
    assert_match "#{@person.email} requested access to #{@workspace.name}", response.body
    assert_select "[data-access-request-step=show] blockquote", text: "I edit"
    assert_equal 1, response.body.scan("I edit").size
    assert_select "p.mt-2.fp-type-body--lg", text: requested_on
    assert_equal 1, response.body.scan(requested_on).size
    assert_select "[data-access-request-step=show] p", text: requested_on, count: 0
    refute_match "What happened", response.body
    refute_match "Asked for access", response.body
    assert_select "[role=tablist].border-b"
    assert_select "[role=tab][aria-selected=true]", text: "Approve"
    assert_select "[role=tab]", text: "Deny"
    assert_select "form.gap-8", count: 2
    assert_select "form.gap-8 .pt-6 button[type=submit]", text: "Approve"
    assert_select "form.gap-8 .pt-6 button[type=submit]", text: "Deny"
    assert_select "form[action=?]", transition_path(request_recording), count: 2
    assert_role_buttons("edit")
    assert_select "input[name=status][value=approved]"
    assert_select "textarea[name=review_note]"
    assert_select "label", text: "Reply message (optional)"
    assert_access_request_screen("show", page: true)

    get request_show_path(request_recording, presentation: "modal"), headers: modal_headers
    assert_select "[data-access-request-step=show] blockquote", text: "I edit"
    assert_select "form.gap-8 .pt-6 button[type=submit]", text: "Approve"
    assert_select "form.gap-8 .pt-6 button[type=submit]", text: "Deny"
    assert_select "[data-access-request-step=show] h1 + p", text: requested_on
    assert_equal 1, response.body.scan(requested_on).size
    assert_select "p.mt-2.fp-type-body--lg", text: requested_on, count: 1
    assert_select "[role=tablist].border-b"
    assert_select "form.gap-8", count: 2
    assert_role_buttons("edit")
    assert_access_request_screen("show", page: false)

    post transition_path(request_recording), params: { status: "approved", role: "edit" }
    follow_redirect!
    assert_match "Request approved.", response.body
    refute_match "What happened", response.body
    assert_select "[role=tab][aria-selected=true]", text: "Approve"
    assert RecordingStudioAccessible.authorized?(actor: @person, recording: @recording, role: "edit")

    post transition_path(request_recording),
         params: { status: "denied", review_note: "Not this round", presentation: "modal" },
         headers: modal_headers
    assert_response :redirect
    assert_includes response.redirect_url, "presentation=modal"
    follow_redirect!(headers: modal_headers)
    assert_match "Request denied.", response.body
    assert_select "[role=tab][aria-selected=true]", text: "Deny"
    assert_access_request_screen("show", page: false)
    refute RecordingStudioAccessible.authorized?(actor: @person, recording: @recording, role: "edit")
  end

  test "a request with no message shows the date only as the subtitle" do
    request_recording = RecordingStudioAccessible.request_access(
      recording: @recording, actor: @person
    ).value
    sign_in @manager
    requested_on = "Requested #{I18n.l(request_recording.created_at.to_date, format: :long)}"

    get request_show_path(request_recording)
    assert_select "p.mt-2.fp-type-body--lg", text: requested_on
    assert_equal 1, response.body.scan(requested_on).size
    assert_select "[data-access-request-step=show] > .grid.gap-3", count: 0

    get request_show_path(request_recording, presentation: "modal"), headers: modal_headers
    assert_select "[data-access-request-step=show] h1 + p", text: requested_on
    assert_select "[data-access-request-step=show] > .grid.gap-3 > p", count: 0
    assert_equal 1, response.body.scan(requested_on).size
  end

  test "a request cannot be opened under another recording" do
    other = create_root_recording(Workspace.create!(name: "Other Request Workspace"))
    create_direct_access_recording(actor: @manager, role: :admin, parent_recording: other)
    note = "hidden-note-#{SecureRandom.hex(8)}"
    request_recording = RecordingStudioAccessible.request_access(
      recording: other, actor: @manager, message: note
    ).value

    sign_in @manager
    get recording_studio_accessible.recording_access_request_path(@recording, request_recording)

    assert_response :not_found
    refute_match note, response.body
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
    assert_select "[data-controller='flat-pack--modal'][id^='access-request-']"
    assert_equal 1, response.body.scan("turbo:before-cache").size
    assert_match "[data-controller='flat-pack--modal'][id^='access-request-']", response.body
    assert_match "recordingStudioAccessibleAccessRequest", response.body
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

  def sent_path(**params)
    recording_studio_accessible.sent_recording_access_requests_path(@recording, **params)
  end

  def modal_headers
    { "Turbo-Frame" => "access_request" }
  end

  def assert_access_request_table
    headers = css_select("table thead th").map { |node| node.text.squish }
    assert_equal [ "Name", "Status", "Actions" ], headers
    assert_select "table tbody tr", count: 1
    assert response.body.index("<thead") < response.body.index("<tbody")
  end

  def refute_recording_subtitle
    refute_match @workspace.name, response.body
  end

  def refute_role_picker
    assert_select "input[type=radio][name='access_request[role]']", count: 0
    refute_match "What do you need?", response.body
  end

  def request_show_path(request_recording, **params)
    recording_studio_accessible.recording_access_request_path(@recording, request_recording, **params)
  end

  def transition_path(request_recording)
    recording_studio_accessible.transition_recording_access_request_path(@recording, request_recording)
  end

  def assert_access_request_screen(step, page:)
    assert_select "turbo-frame#access_request"
    assert_select "[data-access-request-step=?]", step
    if page
      assert_match "<html", response.body
    else
      refute_match(/<html/i, response.body)
    end
  end

  def assert_role_buttons(selected)
    assert_select "button[name=role]", count: 0
    assert_select "input[type=radio][name=role]", count: 3
    assert_select "input[type=radio][name=role][value=?][checked]", selected
    { "view" => "eye", "edit" => "pencil", "admin" => "shield-check" }.each do |role, icon|
      assert_select "input[type=radio][name=role][value=?]", role do |inputs|
        assert_select inputs.first.parent, "[data-flat-pack--icon-name-value=?]", icon
      end
    end
  end
end
