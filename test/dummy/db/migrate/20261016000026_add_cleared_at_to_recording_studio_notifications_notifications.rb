# frozen_string_literal: true

class AddClearedAtToRecordingStudioNotificationsNotifications < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_notifications_notifications, :cleared_at, :datetime
  end
end
