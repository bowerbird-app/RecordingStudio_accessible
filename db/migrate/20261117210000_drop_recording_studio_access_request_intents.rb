# frozen_string_literal: true

class DropRecordingStudioAccessRequestIntents < ActiveRecord::Migration[8.1]
  def change
    drop_table :recording_studio_access_request_intents, if_exists: true
  end
end
