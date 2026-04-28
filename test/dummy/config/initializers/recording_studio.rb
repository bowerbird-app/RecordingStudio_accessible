# frozen_string_literal: true

RecordingStudio.configure do |config|
  config.recordable_types = [ "Workspace", "Folder", "Page" ]
  config.actor = -> { Current.actor }
  config.event_notifications_enabled = true
  config.idempotency_mode = :return_existing
  config.include_children = false
  config.recordable_dup_strategy = :dup
end
