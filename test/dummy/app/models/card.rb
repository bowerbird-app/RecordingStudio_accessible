class Card < ApplicationRecord
  recording_studio_recordable label: "Card", root: false, allowed_parent_types: ["Page"]

  belongs_to :page

  validates :title, :body, presence: true
end
