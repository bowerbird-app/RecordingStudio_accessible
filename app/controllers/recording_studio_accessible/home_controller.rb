# frozen_string_literal: true

module RecordingStudioAccessible
  class HomeController < ApplicationController
    SAMPLE_RECIPIENT_EMAIL = "viewer@example.com"
    SAMPLE_SENDER_EMAIL = "admin@example.com"
    SAMPLE_SENDER_NAME = "Admin"
    SAMPLE_RECORDING_LABEL = "Sample workspace"
    SAMPLE_ACCESS_URL = "https://example.com/sample"

    before_action :authorize_mounted_page!

    def index
      @integration_mode = RecordingStudioAccessible::Compatibility.integration_mode
      @sample_people = [
        { label: Copy.t("home.index.sample_admin"), email: SAMPLE_SENDER_EMAIL },
        { label: Copy.t("home.index.sample_viewer"), email: SAMPLE_RECIPIENT_EMAIL }
      ]
    end

    def overview; end

    def access_methods
      @method_sections = [
        {
          title: Copy.t("home.methods.bootstrap_title"),
          code: <<~'RUBY'.strip
            RecordingStudioAccessible.bootstrap_owner_access!(
              recording: recording,
              actor: user
            )
          RUBY
        },
        {
          title: Copy.t("home.methods.grant_title"),
          code: <<~'RUBY'.strip
            RecordingStudioAccessible.grant_access(
              recording: recording,
              actor: user,
              role: :view,
              manager_actor: current_actor
            )
          RUBY
        },
        {
          title: Copy.t("home.methods.role_for_title"),
          code: <<~'RUBY'.strip
            RecordingStudioAccessible.role_for(
              actor: user,
              recording: recording
            )
          RUBY
        },
        {
          title: Copy.t("home.methods.authorized_title"),
          code: <<~'RUBY'.strip
            RecordingStudioAccessible.authorized?(
              actor: user,
              recording: recording,
              role: :edit
            )
          RUBY
        },
        {
          title: Copy.t("home.methods.root_recordings_title"),
          code: <<~'RUBY'.strip
            RecordingStudioAccessible.root_recordings_for(
              actor: user,
              minimum_role: :view
            )
          RUBY
        },
        {
          title: Copy.t("home.methods.root_recording_ids_title"),
          code: <<~RUBY.strip
            RecordingStudioAccessible.root_recording_ids_for(
              actor: user,
              minimum_role: :edit
            )
          RUBY
        },
        {
          title: Copy.t("home.methods.recordings_title"),
          code: <<~RUBY.strip
            RecordingStudioAccessible.recordings_for(
              actor: user,
              parent_recording: recording,
              minimum_role: :view,
              recordable_type: "MessageGroup"
            )
          RUBY
        },
        {
          title: Copy.t("home.methods.recording_ids_title"),
          code: <<~RUBY.strip
            RecordingStudioAccessible.recording_ids_for(
              actor: user,
              parent_recording: recording,
              recordable_type: "MessageGroup"
            )
          RUBY
        },
        {
          title: Copy.t("home.methods.access_recordings_title"),
          code: <<~RUBY.strip
            RecordingStudioAccessible.access_recordings_for(recording)
          RUBY
        }
      ]

      render :methods
    end

    def user_invites
      @invite_status_rows = [
        {
          title: "unresolved",
          badge_style: :default,
          body: Copy.t("home.user_invites.statuses.unresolved")
        },
        {
          title: "found",
          badge_style: :default,
          body: Copy.t("home.user_invites.statuses.found")
        },
        {
          title: "created",
          badge_style: :info,
          body: Copy.t("home.user_invites.statuses.created")
        },
        {
          title: "invited",
          badge_style: :default,
          body: Copy.t("home.user_invites.statuses.invited")
        },
        {
          title: "requires_resolution",
          badge_style: :info,
          body: Copy.t("home.user_invites.statuses.requires_resolution")
        },
        {
          title: "invalid",
          badge_style: :default,
          body: Copy.t("home.user_invites.statuses.invalid")
        }
      ]

      @invite_setup_examples = [
        {
          title: Copy.t("home.user_invites.setup.find_existing_title"),
          body: Copy.t("home.user_invites.setup.find_existing_body"),
          code: <<~'RUBY'.strip
            config.access_management_actor_email_resolver = lambda do |controller:, email:|
              User.find_by(email: email.to_s.strip.downcase)
            end
          RUBY
        },
        {
          title: Copy.t("home.user_invites.setup.block_until_trusted_title"),
          body: Copy.t("home.user_invites.setup.block_until_trusted_body"),
          code: <<~'RUBY'.strip
            config.access_management_missing_actor_handler = lambda do |email:, **|
              normalized_email = email.to_s.strip.downcase
              next RecordingStudioAccessible::MissingActorResolution.invalid(error: "User is required") if normalized_email.blank?

              RecordingStudioAccessible::MissingActorResolution.invalid(
                error: "Invite #{normalized_email} in your user-management flow before granting access"
              )
            end
          RUBY
        },
        {
          title: Copy.t("home.user_invites.setup.redirect_resolution_title"),
          body: Copy.t("home.user_invites.setup.redirect_resolution_body"),
          code: <<~'RUBY'.strip
            config.access_management_missing_actor_handler = lambda do |controller:, email:, **|
              normalized_email = email.to_s.strip.downcase
              next RecordingStudioAccessible::MissingActorResolution.invalid(error: "User is required") if normalized_email.blank?

              RecordingStudioAccessible::MissingActorResolution.redirect(
                location: controller.main_app.url_for(
                  controller: "/users",
                  action: :new,
                  email: normalized_email,
                  only_path: true
                ),
                alert: "Review #{normalized_email} before granting access",
                status: :requires_resolution
              )
            end
          RUBY
        }
      ]
    end

    def email_template
      recipient = sample_actor(email: SAMPLE_RECIPIENT_EMAIL, name: "Viewer")
      sender = sample_actor(email: SAMPLE_SENDER_EMAIL, name: SAMPLE_SENDER_NAME)
      recording = sample_recording(SAMPLE_RECORDING_LABEL)
      @preview_sender_label = RecordingStudioAccessible::AccessGrantedMailer.display_label_for(sender)
      @preview_sender_email = SAMPLE_SENDER_EMAIL
      @preview_role = :view

      preview_params = {
        recording: recording,
        actor: recipient,
        role: @preview_role.to_s,
        manager_actor: sender,
        access_url: SAMPLE_ACCESS_URL,
        subject: Copy.t("mailers.granted.subject_with_recording", recording: SAMPLE_RECORDING_LABEL)
      }

      preview_message = RecordingStudioAccessible::AccessGrantedMailer.with(preview_params).access_granted.message
      @preview_headers = {
        subject: preview_message.subject,
        from: Array(preview_message.from).join(", "),
        to: Array(preview_message.to).join(", ")
      }
      @preview_html_body = normalize_preview_body(
        preview_message.html_part&.decoded || render_email_preview(format: :html, assigns: preview_params)
      )
      @preview_text_body = normalize_preview_body(
        preview_message.text_part&.decoded || render_email_preview(format: :text, assigns: preview_params)
      )
    end

    private

    def authorize_mounted_page!
      return if RecordingStudioAccessible.configuration.authorize_mounted_page?(
        controller: self,
        actor: current_actor,
        recording: nil
      )

      redirect_to unauthorized_mounted_page_redirect_path
    end

    def current_actor
      RecordingStudioAccessible.configuration.current_actor_for(controller: self)
    end

    def unauthorized_mounted_page_redirect_path
      return main_app.root_path if respond_to?(:main_app) && main_app.respond_to?(:root_path)

      "/"
    end

    def sample_actor(email:, name:)
      Struct.new(:email, :name).new(email, name)
    end

    def sample_recording(label)
      recordable = Struct.new(:name).new(label)
      Struct.new(:recordable).new(recordable)
    end

    def render_email_preview(format:, assigns:)
      render_to_string(
        template: "recording_studio_accessible/access_granted_mailer/access_granted",
        layout: false,
        formats: [format],
        assigns: assigns
      )
    end

    def normalize_preview_body(body)
      normalized = body.to_s.dup.force_encoding(Encoding::UTF_8)
      normalized.valid_encoding? ? normalized : normalized.scrub
    end
  end
end
