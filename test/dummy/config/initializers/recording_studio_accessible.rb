# frozen_string_literal: true

require "securerandom"

RecordingStudioAccessible.configure do |config|
  config.access_actor_types = [ "User" ]

  config.authorize_actor_through = lambda do |actor:, through:, **|
    case through
    when Workspace
      workspace_root = RecordingStudio.root_recording_for(through)

      RecordingStudioAccessible.authorized?(
        actor: actor,
        recording: workspace_root,
        role: :view
      )
    else
      actor == through
    end
  end

  config.avatar_resolver = lambda do |access_holder|
    next unless access_holder.is_a?(User)

    email = access_holder.email.to_s.strip
    next if email.blank?

    {
      name: email.split("@").first.tr("._-", " ").squish.titleize,
      alt: email,
      href: "/users/#{access_holder.id}"
    }
  end

  config.access_management_missing_actor_handler = lambda do |email:, **|
    normalized_email = email.to_s.strip.downcase

    next RecordingStudioAccessible::MissingActorResolution.invalid(error: "User is required") if normalized_email.blank?

    user = User.find_or_initialize_by(email: normalized_email)

    if user.new_record?
      password = SecureRandom.hex(12)
      user.password = password
      user.password_confirmation = password
      user.save!
    end

    RecordingStudioAccessible::MissingActorResolution.created(
      actor: user,
      notice: "Access granted to #{normalized_email}"
    )
  end
end
