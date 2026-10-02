# frozen_string_literal: true

class ChangeRecordingStudioAccessesRoleToString < ActiveRecord::Migration[8.1]
  def up
    change_column_default :recording_studio_accesses, :role, nil

    change_column :recording_studio_accesses, :role, :string, null: false, using: <<~SQL.squish
      CASE role
        WHEN 0 THEN 'view'
        WHEN 1 THEN 'edit'
        WHEN 2 THEN 'admin'
        ELSE 'view'
      END
    SQL

    change_column_default :recording_studio_accesses, :role, "view"
  end

  def down
    change_column_default :recording_studio_accesses, :role, nil

    change_column :recording_studio_accesses, :role, :integer, null: false, using: <<~SQL.squish
      CASE role
        WHEN 'view' THEN 0
        WHEN 'edit' THEN 1
        WHEN 'admin' THEN 2
        ELSE 0
      END
    SQL

    change_column_default :recording_studio_accesses, :role, 0
  end
end
