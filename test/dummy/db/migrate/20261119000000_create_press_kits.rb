# frozen_string_literal: true

class CreatePressKits < ActiveRecord::Migration[8.1]
  def change
    create_table :press_kits, id: :uuid do |t|
      t.references :workspace, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.string :summary, null: false
      t.timestamps
    end
  end
end
