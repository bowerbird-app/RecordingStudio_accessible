# frozen_string_literal: true

class AddRollupReservationToRecordingStudioNotificationsDeliveries < ActiveRecord::Migration[8.1]
  def change
    add_column :recording_studio_notifications_deliveries, :rollup_reserved_at, :datetime
    add_index :recording_studio_notifications_deliveries, %i[status rollup_reserved_at],
              name: "idx_rsn_deliveries_rollup_reservation"
  end
end
