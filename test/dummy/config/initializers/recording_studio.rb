# frozen_string_literal: true

RecordingStudio.configure do |config|
  config.recordable_types = [
    "Workspace", "Folder", "Page", "Card", "MessageRoot", "MessageGroup", "StaffRoot",
    "RecordingStudioUser::People", "RecordingStudioUser::Profile",
    "RecordingStudioAttachable::Attachment"
  ]
  config.actor = -> { Current.actor }
  config.impersonator = -> { Current.method_defined?(:impersonator) ? Current.impersonator : nil }
  # Recording Studio 7 denies record! and create_root_recording! unless an
  # authorizer is set. A present actor may write, including a new root where
  # root_recording is nil. Seeds set Current.actor. Tests resolve an actor
  # when Current.actor is blank. Do not set allow_unauthorized_writes.
  config.authorize_write = ->(actor:, **) { actor.present? }
  config.event_notifications_enabled = true
  config.idempotency_mode = :return_existing
  config.include_children = false if config.respond_to?(:include_children=)
  config.require_recordable_declarations = true
  config.recordable_dup_strategy = :dup
end
