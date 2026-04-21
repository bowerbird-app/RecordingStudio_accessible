# frozen_string_literal: true

module RecordingStudio
  class AccessBoundary < ApplicationRecord
    self.table_name = "recording_studio_access_boundaries"

    include RecordingStudio::Recordable

    enum :minimum_role, { view: 0, edit: 1, admin: 2 }

    def self.recordable_type_label
      "Access boundary"
    end

    class << self
      alias recording_studio_type_label recordable_type_label
    end

    def recordable_name
      minimum = minimum_role.to_s.squish.presence
      minimum.present? ? "Access boundary (min: #{minimum})" : "Access boundary"
    end

    alias recording_studio_label recordable_name
  end
end
