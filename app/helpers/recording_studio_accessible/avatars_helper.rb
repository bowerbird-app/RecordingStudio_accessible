# frozen_string_literal: true

module RecordingStudioAccessible
  module AvatarsHelper
    def recording_studio_accessible_avatars(recording, button_style: nil)
      avatar_items = recording_studio_accessible_avatar_items(recording)

      return recording_studio_accessible_access_button(recording, button_style: button_style) if avatar_items.blank?

      render FlatPack::Tooltip::Component.new(text: "Manage access", placement: :top) do
        render FlatPack::AvatarGroup::Component.new(
          items: avatar_items,
          max: 5,
          size: :sm,
          overlap: :md,
          show_overflow: true,
          overflow_href: recording_studio_accessible_access_management_path(recording)
        )
      end
    end

    private

    def recording_studio_accessible_avatar_items(recording)
      recording_studio_accessible_access_holders(recording).filter_map do |access_holder|
        RecordingStudioAccessible.configuration.avatar_for(access_holder)
      end
    end

    def recording_studio_accessible_access_holders(recording)
      return [] unless recording

      access_recordings = RecordingStudioAccessible.access_recordings_for(recording)
      access_recordings = access_recordings.order(created_at: :asc, id: :asc) if access_recordings.respond_to?(:order)

      access_recordings.filter_map do |access_recording|
        access_recording.recordable&.actor
      end
    end

    def recording_studio_accessible_access_button(recording, button_style:)
      render FlatPack::Button::Component.new(
        text: "+ Access",
        style: button_style || :default,
        size: :sm,
        url: recording_studio_accessible_access_management_path(recording)
      )
    end

    def recording_studio_accessible_access_management_path(recording)
      if respond_to?(:recording_access_management_path)
        recording_access_management_path(recording)
      elsif respond_to?(:recording_studio_accessible) &&
            recording_studio_accessible.respond_to?(:recording_accesses_path)
        recording_studio_accessible.recording_accesses_path(recording)
      elsif respond_to?(:recording_accesses_path)
        recording_accesses_path(recording)
      else
        RecordingStudioAccessible::Engine.routes.url_helpers.recording_accesses_path(recording)
      end
    end
  end
end
