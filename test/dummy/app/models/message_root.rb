class MessageRoot < ApplicationRecord
  recording_studio_recordable label: "Messages", root: true, shared: true

  has_many :message_groups, -> { order(:position, :name) }, dependent: :destroy

  validates :name, presence: true
end
