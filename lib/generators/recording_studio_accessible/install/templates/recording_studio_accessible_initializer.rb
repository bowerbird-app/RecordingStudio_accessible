# frozen_string_literal: true

RecordingStudioAccessible.configure do |config|
  # Keep this enabled if you want an info-level log when RecordingStudio still owns
  # the built-in access constants and this addon is running in compatibility mode.
  config.warn_on_core_conflict = true
end
