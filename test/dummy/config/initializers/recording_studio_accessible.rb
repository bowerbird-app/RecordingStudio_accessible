# frozen_string_literal: true

require "securerandom"

RecordingStudioAccessible.configure do |config|
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
