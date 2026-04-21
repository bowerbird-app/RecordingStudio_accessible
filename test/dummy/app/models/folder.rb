class Folder < ApplicationRecord
  belongs_to :workspace
  has_many :pages, -> { order(:position, :title) }, dependent: :destroy

  validates :name, presence: true
end
