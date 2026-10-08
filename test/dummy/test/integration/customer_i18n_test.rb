# frozen_string_literal: true

require_relative "../test_helper"

class CustomerI18nTest < ActionDispatch::IntegrationTest
  setup do
    ActionMailer::Base.deliveries.clear
    @admin = User.find_by(email: "admin@admin.com") ||
             User.create!(email: "admin@admin.com", password: "Password", password_confirmation: "Password")
    @editor = User.find_by(email: "editor@admin.com") ||
              User.create!(email: "editor@admin.com", password: "Password", password_confirmation: "Password")
    workspace = Workspace.create!(name: "I18n Workspace")
    @recording = create_root_recording(workspace)
    bootstrap = RecordingStudioAccessible.bootstrap_owner_access!(recording: @recording, actor: @admin)
    assert bootstrap.success?, bootstrap.error
    RecordingStudioAccessible.grant_access(recording: @recording, actor: @editor, role: :edit, manager_actor: @admin)
  end

  test "language selector sits in the dummy top nav left of the root switcher" do
    sign_in @admin
    get "/"

    assert_response :success
    assert_select "form[action='/recording_studio_internationalization/locale']"
    assert_includes response.body, "English"
    assert_includes response.body, "Français"
    assert_select "html[lang='en']"
    header = response.body[/<header[\s\S]*?<\/header>/].to_s
    language_at = header.index("dummy-language-selector")
    switcher_at = header.index("recording-studio-root-switchable--root-switch-dropdown")
    assert language_at, "expected a language selector in the top nav"
    assert switcher_at, "expected a root switcher in the top nav"
    assert language_at < switcher_at, "language selector should sit left of the root switcher"
  end

  test "invitee page, mailer and manage-access copy stay English by default" do
    sign_in @admin
    post "/recording_studio_accessible/recordings/#{@recording.id}/accesses", params: {
      access: { email: "invitee@example.com", role: "view" }
    }

    assert_equal "Invitation sent.", flash[:notice]
    follow_redirect!
    assert_includes response.body, "Manage access"
    assert_includes response.body, "Pending invitation"
    assert_includes response.body, "People with access"
    assert_includes response.body, "Add access"
    assert_select "html[lang='en']"

    delivery = ActionMailer::Base.deliveries.last
    assert_equal "You were invited to I18n Workspace", delivery.subject
    assert_includes delivery.body.encoded, "Accept the invitation"
    assert_includes delivery.text_part.decoded, "invited you to view access to I18n Workspace"

    token = delivery.body.encoded[%r{access_invitations/([A-Za-z0-9_-]+)}, 1]
    sign_out @admin
    sign_in User.create!(email: "invitee@example.com", password: "Password", password_confirmation: "Password")
    get "/recording_studio_accessible/access_invitations/#{token}"

    assert_response :success
    assert_includes response.body, "Accept invitation"
    assert_includes response.body, "State pending"
    assert_select "html[lang='en']"

    sign_out :user
    sign_in @admin
    get "/recording_studio_accessible/recordings/#{@recording.id}/accesses/new"
    assert_response :success
    assert_includes response.body, "New access"
    assert_includes response.body, "User email"
    assert_includes response.body, "Create access"
  end

  test "dummy French locale renders invitee page, mailer and manage-access copy" do
    sign_in @admin
    switch_to_french

    post "/recording_studio_accessible/recordings/#{@recording.id}/accesses", params: {
      access: { email: "invitee.fr@example.com", role: "view" }
    }

    assert_equal "Invitation envoyée.", flash[:notice]
    follow_redirect!
    assert_includes response.body, "Gérer l’accès"
    assert_includes response.body, "Invitation en attente"
    assert_includes response.body, "Personnes avec accès"
    assert_includes response.body, "Ajouter un accès"
    refute_includes response.body, "Pending invitation"
    refute_includes response.body, "Manage access"
    assert_select "html[lang='fr']"
    assert_includes response.body, "I18n Workspace"
    assert_includes response.body, @editor.email

    delivery = ActionMailer::Base.deliveries.last
    assert_equal "Vous avez été invité à I18n Workspace", delivery.subject
    html_body = delivery.html_part.decoded
    text_body = delivery.text_part.decoded
    assert_match(/Accepter l.invitation/, html_body)
    assert_match(/Accepter l.invitation/, text_body)
    refute_includes html_body, "Accept the invitation"

    token = delivery.body.encoded[%r{access_invitations/([A-Za-z0-9_-]+)}, 1]
    sign_out @admin
    sign_in User.create!(email: "invitee.fr@example.com", password: "Password", password_confirmation: "Password")
    get "/recording_studio_accessible/access_invitations/#{token}"

    assert_response :success
    assert_includes response.body, "Accepter l’invitation"
    assert_includes response.body, "État en attente"
    refute_includes response.body, "Accept invitation"
    assert_select "html[lang='fr']"

    sign_out :user
    sign_in @admin
    get "/recording_studio_accessible/recordings/#{@recording.id}/accesses/new"
    assert_response :success
    assert_includes response.body, "Nouvel accès"
    assert_includes response.body, "E-mail de la personne"
    assert_includes response.body, "Créer l’accès"
    refute_includes response.body, "New access"
  end

  test "config subject override still wins over French locale" do
    configuration = RecordingStudioAccessible.configuration
    previous_subject = configuration.access_invitation_subject
    configuration.access_invitation_subject = ->(**) { "Host invite subject" }

    sign_in @admin
    switch_to_french
    post "/recording_studio_accessible/recordings/#{@recording.id}/accesses", params: {
      access: { email: "override@example.com", role: "view" }
    }

    assert_equal "Host invite subject", ActionMailer::Base.deliveries.last.subject
    assert_equal "Invitation envoyée.", flash[:notice]
  ensure
    configuration.access_invitation_subject = previous_subject
  end

  private

  def switch_to_french
    patch "/recording_studio_internationalization/locale", params: { locale: "fr", return_to: "/" }
    follow_redirect!
  end
end
