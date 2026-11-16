# frozen_string_literal: true

class StaffRoot < ApplicationRecord
  recording_studio_recordable label: "Staff", root: true
  RecordingStudio.enable_capability(:accessible, on: self)

  validates :name, presence: true
end
