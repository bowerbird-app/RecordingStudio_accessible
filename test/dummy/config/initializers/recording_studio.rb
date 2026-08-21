# frozen_string_literal: true

RecordingStudio.configure do |config|
  config.recordable_types = [ "Workspace", "Folder", "Page", "Card", "MessageRoot", "MessageGroup" ]
  config.actor = -> { Current.actor }
  config.impersonator = -> { Current.method_defined?(:impersonator) ? Current.impersonator : nil }
  config.event_notifications_enabled = true
  config.idempotency_mode = :return_existing
  config.include_children = false if config.respond_to?(:include_children=)
  config.require_recordable_declarations = true
  config.recordable_dup_strategy = :dup
end
