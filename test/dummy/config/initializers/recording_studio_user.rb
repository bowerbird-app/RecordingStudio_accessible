# frozen_string_literal: true

# Email codes for access requests. Do not replace the host Devise routes:
# the dummy sign-in page stays on Devise. Users already depends on this gem,
# so this file only turns OTP on for the dummy app.
RecordingStudioUser.configure do |config|
  config.user_class_name = "User"
  config.mount_path = "/recording_studio_users"
  config.otp_enabled = true
  config.omniauth_providers = {}
end
