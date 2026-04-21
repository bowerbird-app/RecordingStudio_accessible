class CreateDemoContent < ActiveRecord::Migration[8.1]
  def change
    create_table :folders, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :workspace, null: false, type: :uuid, foreign_key: true
      t.string :name, null: false
      t.string :summary, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :pages, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :folder, null: false, type: :uuid, foreign_key: true
      t.string :title, null: false
      t.string :summary, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    create_table :cards, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :page, null: false, type: :uuid, foreign_key: true
      t.string :title, null: false
      t.text :body, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :folders, [:workspace_id, :position]
    add_index :pages, [:folder_id, :position]
    add_index :cards, [:page_id, :position]
  end
end
