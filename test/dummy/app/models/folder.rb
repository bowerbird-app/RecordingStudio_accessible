class Folder < ApplicationRecord
  recording_studio_recordable label: "Folder", root: false, allowed_parent_types: [ "Workspace" ]
  RecordingStudio.enable_capability(:accessible, on: self)

  belongs_to :workspace
  has_many :pages, -> { order(:position, :title) }, dependent: :destroy

  validates :name, presence: true
end
