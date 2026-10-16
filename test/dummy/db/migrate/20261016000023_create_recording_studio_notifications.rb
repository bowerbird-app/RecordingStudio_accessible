# frozen_string_literal: true

class CreateRecordingStudioNotifications < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")

    create_table :recording_studio_notifications_notifications, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :notification_type, null: false
      t.string :recipient_type, null: false
      t.uuid :recipient_id, null: false
      t.string :actor_type
      t.uuid :actor_id
      t.string :notifiable_type
      t.uuid :notifiable_id
      t.uuid :recording_id
      t.uuid :root_recording_id
      t.string :title, null: false
      t.text :body
      t.string :url
      t.jsonb :metadata, default: {}, null: false
      t.string :idempotency_key
      t.datetime :read_at
      t.datetime :archived_at

      t.timestamps
    end

    add_index :recording_studio_notifications_notifications, %i[recipient_type recipient_id notification_type],
              name: "idx_rsn_notifications_recipient_type"
    add_index :recording_studio_notifications_notifications, %i[recipient_type recipient_id idempotency_key],
              unique: true,
              where: "idempotency_key IS NOT NULL",
              name: "idx_rsn_notifications_idempotency"
    add_index :recording_studio_notifications_notifications, %i[root_recording_id created_at],
              name: "idx_rsn_notifications_root_created"
    add_index :recording_studio_notifications_notifications, :recording_id,
              name: "idx_rsn_notifications_recording"

    create_table :recording_studio_notifications_deliveries, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :notification_id, null: false
      t.string :channel, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :delivered_at
      t.text :error_message
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :recording_studio_notifications_deliveries, %i[notification_id channel], unique: true,
                                                                                       name: "idx_rsn_deliveries_notification_channel"
    add_index :recording_studio_notifications_deliveries, %i[channel status],
              name: "idx_rsn_deliveries_channel_status"
    add_foreign_key :recording_studio_notifications_deliveries,
                    :recording_studio_notifications_notifications,
                    column: :notification_id

    create_table :recording_studio_notifications_preferences, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :recipient_type, null: false
      t.uuid :recipient_id, null: false
      t.string :notification_type, null: false
      t.string :channel, null: false
      t.boolean :enabled, null: false, default: true

      t.timestamps
    end

    add_index :recording_studio_notifications_preferences,
              %i[recipient_type recipient_id notification_type channel],
              unique: true,
              name: "idx_rsn_preferences_recipient_type"
    add_index :recording_studio_notifications_preferences, %i[notification_type channel],
              name: "idx_rsn_preferences_type_channel"
  end
end
