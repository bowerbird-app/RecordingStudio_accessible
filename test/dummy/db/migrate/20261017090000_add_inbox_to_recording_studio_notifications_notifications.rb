# frozen_string_literal: true

class AddInboxToRecordingStudioNotificationsNotifications < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_notifications_notifications, :inbox, :boolean, null: false, default: true
  end
end
