class Folder < ApplicationRecord
  include RecordingStudioAccessible::AllowsAccessibleChildren

  recording_studio_recordable label: "Folder", root: false, allowed_parent_types: ["Workspace"]
  recording_studio_accessible_children :access

  belongs_to :workspace
  has_many :pages, -> { order(:position, :title) }, dependent: :destroy

  validates :name, presence: true
end
