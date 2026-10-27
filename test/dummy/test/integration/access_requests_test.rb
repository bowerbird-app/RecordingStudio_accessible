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

  test "visitor verifies an email code then sends a request" do
    skip "Recording Studio Users is required for email codes" unless defined?(::RecordingStudioUser)

    get new_request_path
    assert_email_step
    assert_access_request_screen("email", page: true)

    post email_path, params: {
      email: "new-requester@example.com", name: "Ada Lovelace", role: "view", access_action: "read"
    }
    follow_redirect!
    assert_match "Check your email", response.body
    refute_recording_subtitle
    assert_access_request_screen("verify", page: true)
    assert_select "[data-access-request-step=verify] form .pt-6 button[type=submit]", text: "Confirm"
    get verify_path(presentation: "modal"), headers: modal_headers
    assert_match "Check your email", response.body
    refute_recording_subtitle
    assert_access_request_screen("verify", page: false)

    post verify_path, params: { code: otp_code }
    follow_redirect!
    assert_match "Ask for access", response.body
    assert_match "Add a note", response.body
    refute_role_picker
    refute_recording_subtitle
    assert_access_request_screen("form", page: true)
    get new_request_path(presentation: "modal"), headers: modal_headers
    assert_match "Ask for access", response.body
    refute_role_picker
    refute_recording_subtitle
    assert_access_request_screen("form", page: false)

    requester = User.find_by!(email: "new-requester@example.com")
    assert_equal "Ada Lovelace", RecordingStudioUser.display_name_for(requester)

    post request_path, params: { access_request: { message: "Hello from the visitor", action: "read" } }
    follow_redirect!
    assert_match "Request sent", response.body
    refute_recording_subtitle
    get sent_path(presentation: "modal"), headers: modal_headers
    assert_match "Request sent", response.body
    refute_recording_subtitle
    assert_access_request_screen("sent", page: false)
    assert_equal 1, RecordingStudio::AccessRequest.where(status: "pending").count

    sign_in @manager
    get requests_path
    assert_match "Ada Lovelace", response.body
    assert_match "Hello from the visitor", response.body
    assert_select "span.truncate[title='Hello from the visitor']"
    assert_select "button[data-modal-id]", text: "Approve"
    assert_select "button[data-modal-id]", text: "Deny"
    refute_match "Not chosen yet", response.body
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
    assert_email_step
    assert_access_request_screen("email", page: false)
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
    requested_on = "Requested #{I18n.l(request_recording.created_at.to_date, format: :long)}"
    assert_match "#{@person.email} requested access to #{@workspace.name}", response.body
    assert_match "I edit", response.body
    assert_equal 1, response.body.scan("I edit").size
    assert_select "p.mt-2.text-lg", text: requested_on
    assert_equal 1, response.body.scan(requested_on).size
    assert_select "[data-access-request-step=show] p", text: requested_on, count: 0
    refute_match "What happened", response.body
    refute_match "Asked for access", response.body
    assert_select "[role=tablist].border-b"
    assert_select "[role=tab][aria-selected=true]", text: "Approve"
    assert_select "[role=tab]", text: "Deny"
    assert_select "form.gap-8", count: 2
    assert_select "form.gap-8 .pt-6 button[type=submit]", count: 2
    assert_select "form[action=?]", transition_path(request_recording), count: 2
    assert_role_buttons("edit")
    assert_select "input[name=status][value=approved]"
    assert_select "textarea[name=review_note]"
    assert_select "label", text: "Reply message (optional)"
    assert_access_request_screen("show", page: true)

    get request_show_path(request_recording, presentation: "modal"), headers: modal_headers
    assert_match "I edit", response.body
    assert_select "[data-access-request-step=show] h1 + p", text: requested_on
    assert_equal 1, response.body.scan(requested_on).size
    assert_select "p.mt-2.text-lg", count: 0
    assert_select "[role=tablist].border-b"
    assert_select "form.gap-8", count: 2
    assert_select "form.gap-8 .pt-6 button[type=submit]", count: 2
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
    assert_select "p.mt-2.text-lg", text: requested_on
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

  test "a disabled email gets the same code page as any other email" do
    skip "Recording Studio Users is required for email codes" unless defined?(::RecordingStudioUser)

    disabled = create_user("disabled-requester@example.com")
    disabled.confirm if disabled.respond_to?(:confirm)
    with_inactive_email(disabled.email) do
      post email_path, params: { email: disabled.email, name: "Pat Disabled" }
    end

    assert_response :redirect
    follow_redirect!
    assert_match "Check your email", response.body
    refute_match "can&#39;t be used", response.body
    refute_match "can't be used", response.body
    assert_equal 1, User.where(email: disabled.email).count
    assert_nil open_otp_challenge(disabled)
  end

  test "a throttled new email shows the rate limit and creates no user" do
    skip "Recording Studio Users is required for email codes" unless defined?(::RecordingStudioUser)

    email = "throttled-new@example.com"
    digest = RecordingStudioUser::Services::OtpRateLimiter.email_key(email)
    RecordingStudioUser::Services::OtpRateLimiter.allow_request!(scope: :issue, key: digest)

    post email_path, params: { email: email, name: "Ada Lovelace" }

    assert_response :unprocessable_entity
    assert_match "Wait a minute", response.body
    assert_nil User.find_by(email: email)
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
    assert_equal [ "Name", "Note", "Status", "Actions" ], headers
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

  def assert_email_step
    assert_match "Request access", response.body
    assert_match @workspace.name, response.body
    assert_match "Next", response.body
    assert_select "input[name=name]"
    assert_select "input[name=name][required]", count: 0
    assert_select "form .pt-6 button[type=submit]", text: "Next"
    assert_select "h1", text: "Request access"
    assert_select "h2", text: "Request access", count: 0
    refute_match "Tell us where to send the code", response.body
    refute_match "Send code", response.body
  end

  def otp_code
    intent = RecordingStudioAccessible::AccessRequestIntent.order(:created_at).last
    RecordingStudioUser.otp_message(intent.otp_challenge_id).fetch(:body)[/\d{6}/]
  end

  def open_otp_challenge(user)
    RecordingStudioUser::OtpChallenge.find_by(user: user, consumed_at: nil, revoked_at: nil)
  end

  def with_inactive_email(email)
    User.class_eval do
      alias_method :active_for_authentication_without_test_disable, :active_for_authentication?
      define_method(:active_for_authentication?) do
        return false if self.email == email

        active_for_authentication_without_test_disable
      end
    end
    yield
  ensure
    User.class_eval do
      alias_method :active_for_authentication?, :active_for_authentication_without_test_disable
      remove_method :active_for_authentication_without_test_disable
    end
  end
end
