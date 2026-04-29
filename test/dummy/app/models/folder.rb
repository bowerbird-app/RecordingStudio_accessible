class Folder < ApplicationRecord
  include RecordingStudioAccessible::AllowsAccessibleChildren

  recording_studio_accessible_children :access

  belongs_to :workspace
  has_many :pages, -> { order(:position, :title) }, dependent: :destroy

  validates :name, presence: true
end
