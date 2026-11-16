class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  # Users 0.32 no longer confirms a password account on create. The demo and
  # its tests sign in with Devise immediately, so confirm here without going
  # through confirm, which clears a password saved outside the signup session.
  after_create :confirm_password_account, if: :registered_with_password?

  DEMO_AVATAR_PATH = "/demo-avatars/alex-rivera.png"

  def confirm_password_account
    return unless self.class.column_names.include?("confirmed_at")
    return if confirmed_at.present?

    update_column(:confirmed_at, Time.current)
  end

  def image
    DEMO_AVATAR_PATH if email == "admin@admin.com"
  end
end
