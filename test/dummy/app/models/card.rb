class Card < ApplicationRecord
  belongs_to :page

  validates :title, :body, presence: true
end
