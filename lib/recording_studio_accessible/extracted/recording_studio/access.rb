# frozen_string_literal: true

module RecordingStudio
  class Access < ApplicationRecord
    self.table_name = "recording_studio_accesses"

    include RecordingStudio::Recordable

    belongs_to :actor, polymorphic: true

    enum :role, { view: 0, edit: 1, admin: 2 }

    def self.recordable_type_label
      "Access"
    end

    class << self
      alias recording_studio_type_label recordable_type_label
    end

    def recordable_name
      actor_name = actor.respond_to?(:name) ? actor.name.to_s.squish.presence : nil
      actor_text =
        if actor_name.present?
          suffix = actor.class.name.demodulize == "SystemActor" ? "System" : "User"
          "#{actor_name} (#{suffix})"
        else
          "Unknown actor"
        end

      "Access: #{role} — #{actor_text}"
    end

    alias recording_studio_label recordable_name
  end
end
