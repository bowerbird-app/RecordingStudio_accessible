# frozen_string_literal: true

class CreateRecordingStudioAccessInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :recording_studio_access_invitations, id: :uuid do |t|
      t.uuid :recording_id, null: false
      t.string :email, null: false
      t.string :role, null: false
      t.string :token_digest, null: false, limit: 64
      t.string :manager_actor_type, null: false
      t.uuid :manager_actor_id, null: false
      t.string :accepted_by_actor_type
      t.uuid :accepted_by_actor_id
      t.datetime :expires_at, null: false
      t.datetime :last_sent_at, null: false
      t.datetime :accepted_at
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :recording_studio_access_invitations, %i[recording_id email],
              unique: true,
              where: "accepted_at IS NULL AND revoked_at IS NULL",
              name: "idx_rs_access_invitations_one_active"
    add_index :recording_studio_access_invitations, :token_digest,
              unique: true,
              name: "idx_rs_access_invitations_token_digest"
    add_index :recording_studio_access_invitations, :recording_id
    add_foreign_key :recording_studio_access_invitations, :recording_studio_recordings, column: :recording_id
    add_check_constraint :recording_studio_access_invitations,
                         "accepted_at IS NULL OR revoked_at IS NULL",
                         name: "access_invitations_not_accepted_and_revoked"
  end
end
