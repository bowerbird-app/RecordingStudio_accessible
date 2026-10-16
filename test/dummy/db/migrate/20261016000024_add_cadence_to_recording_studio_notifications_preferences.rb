# frozen_string_literal: true

class AddCadenceToRecordingStudioNotificationsPreferences < ActiveRecord::Migration[8.1]
  def change
    change_column_null :recording_studio_notifications_preferences, :channel, true
    change_column_null :recording_studio_notifications_preferences, :enabled, true
    change_column_default :recording_studio_notifications_preferences, :enabled, from: true, to: nil
    add_column :recording_studio_notifications_preferences, :cadence, :string

    remove_index :recording_studio_notifications_preferences, name: "idx_rsn_preferences_recipient_type"
    add_index :recording_studio_notifications_preferences,
              %i[recipient_type recipient_id notification_type channel],
              unique: true,
              where: "channel IS NOT NULL",
              name: "idx_rsn_preferences_channel"
    add_index :recording_studio_notifications_preferences,
              %i[recipient_type recipient_id notification_type],
              unique: true,
              where: "channel IS NULL",
              name: "idx_rsn_preferences_cadence"

    add_check_constraint :recording_studio_notifications_preferences,
                         "(channel IS NOT NULL AND enabled IS NOT NULL AND cadence IS NULL) OR " \
                         "(channel IS NULL AND enabled IS NULL AND cadence IS NOT NULL)",
                         name: "chk_rsn_preferences_shape"
  end
end
