# frozen_string_literal: true

class CreateRecordingStudioAccessBoundaries < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_access_boundaries, id: :uuid do |t|
      t.integer :minimum_role

      t.datetime :created_at, null: false
    end
  end
end
