# frozen_string_literal: true

module RecordingStudioAccessible
  module AvatarsHelper
    def recording_studio_accessible_avatars(recording, button_style: nil)
      return "".html_safe unless recording_studio_accessible_manage_access?(recording)

      avatar_items = recording_studio_accessible_avatar_items(recording)

      return recording_studio_accessible_access_button(recording, button_style: button_style) if avatar_items.blank?

      render recording_studio_accessible_manage_access_tooltip do
        render recording_studio_accessible_avatar_group(recording, avatar_items)
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

    def recording_studio_accessible_manage_access?(recording)
      RecordingStudioAccessible.configuration.authorize_access_management?(
        recording: recording,
        actor: recording_studio_accessible_current_actor,
        controller: self
      )
    end

    def recording_studio_accessible_current_actor
      RecordingStudioAccessible.configuration.current_actor_for(controller: self)
    end

    def recording_studio_accessible_access_button(recording, button_style:)
      render FlatPack::Button::Component.new(
        text: "+ Access",
        style: button_style || :default,
        size: :sm,
        url: recording_studio_accessible_access_management_path(recording)
      )
    end

    def recording_studio_accessible_manage_access_tooltip
      FlatPack::Tooltip::Component.new(text: "Manage access", placement: :top)
    end

    def recording_studio_accessible_avatar_group(recording, avatar_items)
      FlatPack::AvatarGroup::Component.new(
        items: avatar_items,
        max: 5,
        size: :sm,
        overlap: :md,
        show_overflow: true,
        overflow_href: recording_studio_accessible_access_management_path(recording)
      )
    end

    def recording_studio_accessible_access_management_path(recording)
      return unless recording

      route_proxy = recording_studio_accessible_route_proxy
      return recording_access_management_path(recording) if respond_to?(:recording_access_management_path)
      return route_proxy.recording_accesses_path(recording) if route_proxy
      return recording_accesses_path(recording) if respond_to?(:recording_accesses_path)

      RecordingStudioAccessible::Engine.routes.url_helpers.recording_accesses_path(recording)
    end

    def recording_studio_accessible_route_proxy
      respond_to?(:recording_studio_accessible) &&
        recording_studio_accessible.respond_to?(:recording_accesses_path) &&
        recording_studio_accessible
    end
  end
end
