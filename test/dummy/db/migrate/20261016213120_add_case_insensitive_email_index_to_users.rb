# frozen_string_literal: true

class AddCaseInsensitiveEmailIndexToUsers < ActiveRecord::Migration[8.1]
  def up
    add_index :users, "LOWER(email)", unique: true, name: "index_users_on_lower_email"
  end

  def down
    remove_index :users, name: "index_users_on_lower_email"
  end
end
