# frozen_string_literal: true

RecordingStudioAccessible.configure do |config|
  # Keep this enabled if you want an info-level log when RecordingStudio still owns
  # the built-in access constants and this addon is running in compatibility mode.
  config.warn_on_core_conflict = true

  # Optional: resolve the submitted email to an actor for new access grants.
  # config.access_management_actor_email_resolver = lambda do |controller:, email:|
  #   User.find_by(email: email.to_s.strip.downcase)
  # end

  # Optional: customize how actors are labeled in the access management UI.
  # config.access_management_actor_label = ->(actor) { actor.email }

  # Optional: customize who can manage access for a recording.
  # config.access_management_authorizer = lambda do |controller:, recording:|
  #   actor = controller.current_user
  #   actor.present? && RecordingStudio::Services::AccessCheck.allowed?(
  #     actor: actor,
  #     recording: recording,
  #     role: :admin
  #   )
  # end
end