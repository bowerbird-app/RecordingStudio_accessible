# frozen_string_literal: true

RecordingStudioAccessible.configure do |config|
  # Keep this enabled if you want an info-level log when RecordingStudio still owns
  # the built-in access constants and this addon is running in compatibility mode.
  config.warn_on_core_conflict = true

  # New access grants fail closed until their polymorphic actor types are listed.
  # Add each supported host actor class, for example: ["User", "Workspace"].
  config.access_actor_types = ["User"]
  # Set this exact symbol only when arbitrary persisted polymorphic actors are
  # intentionally supported. :all does not enable actor access-point lookup.
  # config.access_actor_types = :all

  # Optional: allow one actor to use another actor's access grants.
  # By default, actors may only act through themselves.
  # config.authorize_actor_through = lambda do |actor:, through:, recording: nil, role: nil, controller: nil, **|
  #   case through
  #   when Workspace
  #     workspace_root = RecordingStudio.root_recording_for(through)
  #     RecordingStudioAccessible.authorized?(actor: actor, recording: workspace_root, role: :view)
  #   else
  #     actor == through
  #   end
  # end

  # Optional: resolve the submitted email to an actor for new access grants.
  # config.access_management_actor_email_resolver = lambda do |controller:, email:|
  #   User.find_by(email: email.to_s.strip.downcase)
  # end

  # Optional: customize how the mounted engine resolves the acting user.
  # By default it uses Current.actor. It does not call current_user at all,
  # public or private. Hosts must set Current.actor or use this hook.
  # config.access_management_current_actor_resolver = lambda do |controller:|
  #   Current.actor || controller.current_user
  # end

  # Optional: customize what happens when no existing user matches the submitted
  # email. The built-in default keeps the current "not found" error until your
  # host app decides how to provision or resolve that recipient.
  #
  # The controller passes these keyword arguments to the handler:
  # - email: the submitted email address
  # - controller: the engine controller instance handling the request
  # - recording: the recording being granted
  # - role: the requested role string
  # - manager_actor: the current actor performing the grant
  #
  # The handler may return:
  # - an actor record to grant access immediately
  # - RecordingStudioAccessible::MissingActorResolution.created(actor: user, notice: ...)
  # - RecordingStudioAccessible::MissingActorResolution.redirect(location: ..., alert: ...)
  # - RecordingStudioAccessible::MissingActorResolution.invalid(error: ...)
  #
  # Prefer :invalid or :requires_resolution until your app has verified the
  # recipient and completed any required setup. Returning an actor or :created
  # continues the original grant immediately.
  #
  # config.access_management_missing_actor_handler = lambda do |controller:, email:, **|
  #   normalized_email = email.to_s.strip.downcase
  #   next RecordingStudioAccessible::MissingActorResolution.invalid(error: "User is required") if normalized_email.blank?
  #
  #   RecordingStudioAccessible::MissingActorResolution.redirect(
  #     location: controller.main_app.url_for(
  #       controller: "/users",
  #       action: :new,
  #       email: normalized_email,
  #       only_path: true
  #     ),
  #     alert: "Review #{normalized_email} before granting access",
  #     status: :requires_resolution
  #   )
  # end

  # Optional: customize the post-grant share email.
  # The built-in notifier sends RecordingStudioAccessible::AccessGrantedMailer
  # after a successful grant using the templates copied to:
  # app/views/recording_studio_accessible/access_granted_mailer/
  #
  # The controller only calls this notifier after the grant service succeeds.
  # Provisioning a user does not send the share email by itself.
  #
  # config.access_management_access_granted_subject = lambda do |recording:, **|
  #   "A recording was shared with you: #{RecordingStudio::Labels.title_for(recording.recordable)}"
  # end
  #
  # config.access_management_access_granted_url_resolver = lambda do |controller:, recording:, **|
  #   controller.main_app.polymorphic_url(recording.recordable)
  # end
  #
  # config.access_management_access_granted_notifier = lambda do |controller:, recording:, actor:, role:, manager_actor:|
  #   RecordingStudioAccessible::AccessGrantedMailer.with(
  #     controller: controller,
  #     recording: recording,
  #     actor: actor,
  #     role: role,
  #     manager_actor: manager_actor,
  #     subject: "A recording was shared with you",
  #     access_url: controller.main_app.polymorphic_url(recording.recordable)
  #   ).access_granted.deliver_now
  # end

  # Optional: override default actor labels (full name, then name, then email).
  # config.access_management_actor_label = ->(actor) { actor.email }

  # Optional: override manage-access row photos. Default duck-types actor.avatar
  # or actor.image, then a Users profile image when that gem is loaded.
  # config.access_management_actor_avatar = ->(actor) { actor.profile_photo_url }

  # Optional: customize avatar data for recording_studio_accessible_avatars.
  # Return nil when an actor should not be rendered as an avatar.
  # config.avatar_resolver = ->(access_holder) do
  #   {
  #     name: access_holder.profile_name,
  #     image_url: access_holder.profile_avatar_url
  #   }
  # end

  # Optional: customize who can manage access for a recording.
  # config.access_management_authorizer = lambda do |recording:, actor:, **|
  #   actor.present? && RecordingStudioAccessible.authorized?(
  #     actor: actor,
  #     recording: recording,
  #     role: :admin
  #   )
  # end

  # Optional: retitle manage-access chrome for one recording. Return nil for
  # the defaults, { scope: "featured_in.teams" }, or a hash of chrome keys.
  # Resolve from the recording. Do not read titles from query params. A raise
  # or junk return keeps the defaults.
  # config.access_management_copy = lambda do |recording:, **|
  #   recordable = recording&.recordable
  #   next unless recordable.is_a?(Workspace) && recordable.name == "Teams"
  #
  #   { scope: "featured_in.teams" }
  # end

  # Optional: refuse a grant the built-in checks would otherwise allow.
  # Default nil means no extra check. Raise GrantRefused to refuse. Do not
  # rescue other errors. Bootstrap of the first owner does not call this.
  # The new-access page passes source :new_access. The invitation page
  # passes source :new_invitation. On those calls role and the grantee
  # actor are nil, and granted_by is the current actor.
  # config.before_access_grant = lambda do |context|
  #   next if context.previous_role.present?
  #
  #   cap = 5
  #   count = RecordingStudioAccessible.access_recordings_for(context.recording).count
  #   next if count < cap
  #
  #   raise RecordingStudioAccessible::GrantRefused.new(
  #     "You've filled every seat. Free one up, or pick a larger plan.",
  #     redirect_to: "/plans"
  #   )
  # end

  # Optional: wrap engine screens in one host layout. Pass a layout name, or a
  # callable that receives `controller:` and returns a layout name. Leave this
  # unset and each screen keeps the layout it uses today. Authentication and
  # access checks still run first. A callable that raises does not let a denied
  # actor through. Access-request modal frames stay without a document layout.
  # config.layout = "admin"
  # config.layout = lambda do |controller:|
  #   "admin"
  # end

  # Optional: customize who can view the mounted addon overview/docs/email-preview
  # pages under /recording_studio_accessible. The default is fail-closed unless
  # the current actor has admin access to the resolved demo root recording.
  # config.mounted_page_authorizer = lambda do |controller:, actor:, recording:|
  #   actor.present? && recording.present? && RecordingStudioAccessible.authorized?(
  #     actor: actor,
  #     recording: recording,
  #     role: :admin
  #   )
  # end

  # Optional: per-action audiences. Opt-in. Existing named-action policies are
  # unchanged until an action is listed here. `granted` is always kept in the
  # allowed set. Enable `:action_audiences` on host types that should hold
  # audience settings, and register custom audiences before they appear in
  # `allowed`.
  #
  # RecordingStudioAccessible.register_audience(
  #   :"presskits.verified_journalist",
  #   label_key: "recording_studio_presskits.audiences.verified_journalist"
  # ) do |actor:, recording:, context:|
  #   false
  # end
  #
  # config.action_audiences[:"presskits.kit_download"] = {
  #   allowed: %i[signed_in granted],
  #   default: :granted,
  #   granted_roles: %i[download edit admin],
  #   granted_override: true,
  #   manage_role: :admin
  # }
end
