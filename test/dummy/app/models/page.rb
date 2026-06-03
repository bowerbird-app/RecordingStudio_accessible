class Page < ApplicationRecord
  recording_studio_recordable label: "Page", root: false, allowed_parent_types: ["Folder"]

  belongs_to :folder
  has_many :cards, -> { order(:position, :title) }, dependent: :destroy

  validates :title, presence: true
end
