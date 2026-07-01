class MessageGroup < ApplicationRecord
  recording_studio_recordable label: "Message group", root: false, allowed_parent_types: [ "MessageRoot" ]
  RecordingStudio.enable_capability(:accessible, on: self)

  belongs_to :message_root

  validates :name, :summary, presence: true
end
