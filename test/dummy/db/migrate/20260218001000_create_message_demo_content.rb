class CreateMessageDemoContent < ActiveRecord::Migration[8.1]
  def change
    create_table :message_roots, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false
      t.timestamps
    end

    create_table :message_groups, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :message_root, null: false, type: :uuid, foreign_key: true
      t.string :name, null: false
      t.string :summary, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :message_groups, [ :message_root_id, :position ]
  end
end
