class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  DEMO_AVATAR_PATH = "/demo-avatars/alex-rivera.png"

  def image
    DEMO_AVATAR_PATH if email == "admin@admin.com"
  end
end
