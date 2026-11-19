# frozen_string_literal: true

class PressKit < ApplicationRecord
  recording_studio_recordable label: "Press kit", root: false, allowed_parent_types: [ "Workspace" ]
  RecordingStudio.enable_capability(:accessible, on: self)

  accessible_roles :view, :download, :edit, :admin

  belongs_to :workspace

  validates :name, presence: true
  validates :summary, presence: true
end
