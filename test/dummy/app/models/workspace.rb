class Workspace < ApplicationRecord
  include RecordingStudioAccessible::AllowsAccessibleChildren

  recording_studio_accessible_children :access

  has_many :folders, -> { order(:position, :name) }, dependent: :destroy

  validates :name, presence: true
end
