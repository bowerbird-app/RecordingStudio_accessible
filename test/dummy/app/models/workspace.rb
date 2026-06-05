class Workspace < ApplicationRecord
  recording_studio_recordable label: "Workspace", root: true
  RecordingStudio.enable_capability(:accessible, on: self)

  has_many :folders, -> { order(:position, :name) }, dependent: :destroy

  validates :name, presence: true
end
