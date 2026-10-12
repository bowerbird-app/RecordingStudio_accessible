# frozen_string_literal: true

module RecordingStudioAccessible
  class HomeController < ApplicationController
    before_action :authorize_mounted_page!

    def index
      @integration_mode = RecordingStudioAccessible::Compatibility.integration_mode
      @workspace = demo_workspace
      @root_recording = find_root_recording
      @admin_user = resolve_admin_user
      @viewer_user = resolve_viewer_user
      @access_rows = build_access_rows
    end

    def overview; end

    def access_methods
      @method_sections = [
        {
          title: Copy.t(
            "home.methods.bootstrap_title",
            default: "Bootstrap the first owner with RecordingStudioAccessible.bootstrap_owner_access!"
          ),
          code: <<~'RUBY'.strip
            RecordingStudioAccessible.bootstrap_owner_access!(
              recording: recording,
              actor: user
            )
          RUBY
        },
        {
          title: Copy.t(
            "home.methods.grant_title",
            default: "Grant access with RecordingStudioAccessible.grant_access"
          ),
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
          title: Copy.t(
            "home.methods.role_for_title",
            default: "Resolve a user's role with RecordingStudioAccessible.role_for"
          ),
          code: <<~'RUBY'.strip
            RecordingStudioAccessible.role_for(
              actor: user,
              recording: recording
            )
          RUBY
        },
        {
          title: Copy.t(
            "home.methods.authorized_title",
            default: "Check authorization with RecordingStudioAccessible.authorized?"
          ),
          code: <<~'RUBY'.strip
            RecordingStudioAccessible.authorized?(
              actor: user,
              recording: recording,
              role: :edit
            )
          RUBY
        },
        {
          title: Copy.t(
            "home.methods.root_recordings_title",
            default: "List accessible roots with RecordingStudioAccessible.root_recordings_for"
          ),
          code: <<~'RUBY'.strip
            RecordingStudioAccessible.root_recordings_for(
              actor: user,
              minimum_role: :view
            )
          RUBY
        },
        {
          title: Copy.t(
            "home.methods.root_recording_ids_title",
            default: "List accessible root ids with RecordingStudioAccessible.root_recording_ids_for"
          ),
          code: <<~RUBY.strip
            RecordingStudioAccessible.root_recording_ids_for(
              actor: user,
              minimum_role: :edit
            )
          RUBY
        },
        {
          title: Copy.t(
            "home.methods.access_recordings_title",
            default: "List direct grants on a recording with RecordingStudioAccessible.access_recordings_for"
          ),
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
          body: Copy.t(
            "home.user_invites.statuses.unresolved",
            default: "The default when no actor matches the email. The access page stores an invitation and sends it."
          )
        },
        {
          title: "found",
          badge_style: :default,
          body: Copy.t(
            "home.user_invites.statuses.found",
            default: "An existing actor was resolved from the submitted email, so the access grant can continue immediately."
          )
        },
        {
          title: "created",
          badge_style: :info,
          body: Copy.t(
            "home.user_invites.statuses.created",
            default: "Use this only after your app has already verified the recipient and finished any setup needed for the same grant request."
          )
        },
        {
          title: "invited",
          badge_style: :default,
          body: Copy.t(
            "home.user_invites.statuses.invited",
            default: "Use this when another invite flow sent the invitation. The addon stores nothing and sends the manager back to the access list with a notice."
          )
        },
        {
          title: "requires_resolution",
          badge_style: :info,
          body: Copy.t(
            "home.user_invites.statuses.requires_resolution",
            default: "Redirect the manager into a setup flow, such as a custom user creation screen, before granting access."
          )
        },
        {
          title: "invalid",
          badge_style: :default,
          body: Copy.t(
            "home.user_invites.statuses.invalid",
            default: "The submitted email could not be used. The form re-renders with the returned error message."
          )
        }
      ]

      @invite_setup_examples = [
        {
          title: Copy.t(
            "home.user_invites.setup.find_existing_title",
            default: "Only find existing users"
          ),
          body: Copy.t(
            "home.user_invites.setup.find_existing_body",
            default: "Use the resolver when your app should only grant access to users that already exist."
          ),
          code: <<~'RUBY'.strip
            config.access_management_actor_email_resolver = lambda do |controller:, email:|
              User.find_by(email: email.to_s.strip.downcase)
            end
          RUBY
        },
        {
          title: Copy.t(
            "home.user_invites.setup.block_until_trusted_title",
            default: "Keep the form blocked until a trusted workflow resolves the email"
          ),
          body: Copy.t(
            "home.user_invites.setup.block_until_trusted_body",
            default: "Prefer returning an error until your app finishes any invite, approval, or verification work for that address."
          ),
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
          title: Copy.t(
            "home.user_invites.setup.redirect_resolution_title",
            default: "Send managers to a resolution flow"
          ),
          body: Copy.t(
            "home.user_invites.setup.redirect_resolution_body",
            default: "Return a redirect-style resolution when a person needs extra setup, approvals, or a richer invite workflow before the grant continues."
          ),
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
      @workspace ||= demo_workspace
      @root_recording ||= find_root_recording
      @admin_user ||= resolve_admin_user
      @viewer_user ||= resolve_viewer_user

      @preview_recipient = resolve_email_template_recipient
      @preview_sender = resolve_email_template_sender || @preview_recipient
      @preview_sender_label = RecordingStudioAccessible::AccessGrantedMailer.display_label_for(@preview_sender)
      @preview_role = :view
      @preview_access_url = resolve_preview_access_url
      @preview_subject = resolve_preview_subject

      preview_params = {
        recording: @root_recording,
        actor: @preview_recipient,
        role: @preview_role.to_s,
        manager_actor: @preview_sender,
        access_url: @preview_access_url,
        subject: @preview_subject
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
        recording: authorization_recording
      )

      redirect_to unauthorized_mounted_page_redirect_path
    end

    def current_actor
      RecordingStudioAccessible.configuration.current_actor_for(controller: self)
    end

    def authorization_recording
      @authorization_recording ||= begin
        @workspace ||= demo_workspace
        @root_recording ||= find_root_recording
      end
    end

    def unauthorized_mounted_page_redirect_path
      return main_app.root_path if respond_to?(:main_app) && main_app.respond_to?(:root_path)

      "/"
    end

    def demo_workspace
      return unless defined?(::Workspace)

      ::Workspace.order(:name, :id).first
    end

    def find_root_recording
      return unless @workspace && defined?(::RecordingStudio::Recording)

      RecordingStudio.root_recording_for(@workspace)
    end

    def resolve_admin_user
      return current_actor if current_actor.present?
      return unless defined?(::User)

      ::User.find_by(email: "admin@admin.com") || ::User.first
    end

    def resolve_viewer_user
      return unless defined?(::User)

      ::User.where.not(id: @admin_user&.id).order(:email).first
    end

    def build_access_rows
      return [] unless @root_recording

      [
        access_row(
          label: @admin_user&.email || Copy.t("home.index.admin_fallback", default: "Admin"),
          actor: @admin_user,
          minimum_role: :admin
        ),
        access_row(
          label: @viewer_user&.email || Copy.t("home.index.viewer_fallback", default: "Viewer"),
          actor: @viewer_user,
          minimum_role: :view
        ),
        access_row(
          label: Copy.t("home.index.anonymous", default: "Anonymous"),
          actor: nil,
          minimum_role: :view
        )
      ]
    end

    def access_row(label:, actor:, minimum_role:)
      {
        label: label,
        role: RecordingStudioAccessible.role_for(actor: actor, recording: @root_recording),
        allowed: RecordingStudioAccessible.authorized?(actor: actor, recording: @root_recording, role: minimum_role)
      }
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

    def resolve_email_template_recipient
      return ::User.find_by(email: "viewer@admin.com") if defined?(::User) && ::User.exists?(email: "viewer@admin.com")

      @viewer_user || @admin_user || current_user
    end

    def resolve_email_template_sender
      return ::User.find_by(email: "admin@admin.com") if defined?(::User) && ::User.exists?(email: "admin@admin.com")

      @admin_user || current_user
    end

    def resolve_preview_access_url
      configuration = RecordingStudioAccessible.configuration
      kwargs = preview_resolution_kwargs

      if configuration.respond_to?(:access_granted_url_for)
        configuration.access_granted_url_for(**kwargs)
      else
        configuration.send(:resolve_access_granted_url, **kwargs)
      end
    end

    def resolve_preview_subject
      configuration = RecordingStudioAccessible.configuration
      kwargs = preview_resolution_kwargs

      if configuration.respond_to?(:access_granted_subject_for)
        configuration.access_granted_subject_for(**kwargs)
      else
        configuration.send(:resolve_access_granted_subject, **kwargs)
      end
    end

    def preview_resolution_kwargs
      {
        controller: self,
        recording: @root_recording,
        actor: @preview_recipient,
        role: @preview_role,
        manager_actor: @preview_sender
      }
    end
  end
end
