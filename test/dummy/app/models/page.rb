class Page < ApplicationRecord
  belongs_to :folder
  has_many :cards, -> { order(:position, :title) }, dependent: :destroy

  validates :title, presence: true
end
