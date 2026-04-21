class Workspace < ApplicationRecord
  has_many :folders, -> { order(:position, :name) }, dependent: :destroy

  validates :name, presence: true
end
