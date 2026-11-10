class Workspace < ApplicationRecord
  recording_studio_recordable label: "Workspace", root: true
  RecordingStudio.enable_capability(:accessible, on: self)
  RecordingStudio.enable_capability(:action_audiences, on: self)
  RecordingStudio.enable_capability(:api_access_point, on: self) if defined?(RecordingStudioApi)

  has_many :folders, -> { order(:position, :name) }, dependent: :destroy

  validates :name, presence: true
end
