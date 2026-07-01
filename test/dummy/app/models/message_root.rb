class MessageRoot < ApplicationRecord
  recording_studio_recordable label: "Message root", root: true
  RecordingStudio.enable_capability(:accessible, on: self)

  has_many :message_groups, -> { order(:position, :name) }, dependent: :destroy

  validates :name, presence: true
end
