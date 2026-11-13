# frozen_string_literal: true

RecordingStudio.configure do |config|
  config.recordable_types = [
    "Workspace", "Folder", "Page", "Card", "MessageRoot", "MessageGroup",
    "RecordingStudioUser::People", "RecordingStudioUser::Profile",
    "RecordingStudioAttachable::Attachment"
  ]
  config.actor = -> { Current.actor }
  config.impersonator = -> { Current.method_defined?(:impersonator) ? Current.impersonator : nil }
  # Recording Studio 6.5+ denies a write with no authorize_write, and denies a
  # write with no actor unless allow_unauthorized_writes is set. Seeds and
  # tests record before anyone is signed in.
  config.allow_unauthorized_writes = true
  config.authorize_write = ->(**) { true }
  config.event_notifications_enabled = true
  config.idempotency_mode = :return_existing
  config.include_children = false if config.respond_to?(:include_children=)
  config.require_recordable_declarations = true
  config.recordable_dup_strategy = :dup
end
