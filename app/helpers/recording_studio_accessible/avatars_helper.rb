# frozen_string_literal: true

module RecordingStudioAccessible
  module AvatarsHelper
    def recording_studio_accessible_avatars(recording, size: :sm, button_size: :sm, button_style: nil, max: 3,
                                            overlap: :sm, scope: :direct)
      return "".html_safe unless recording_studio_accessible_flatpack_available?
      return "".html_safe unless recording_studio_accessible_manage_access?(recording)

      avatar_items = recording_studio_accessible_avatar_items(recording, scope: scope)

      if avatar_items.blank?
        return recording_studio_accessible_access_button(recording, button_size: button_size,
                                                                    button_style: button_style)
      end

      recording_studio_accessible_avatar_actions(
        recording,
        avatar_items,
        size: size,
        max: max,
        overlap: overlap,
        button_size: button_size,
        button_style: button_style
      )
    end

    private

    def recording_studio_accessible_flatpack_available?
      defined?(::FlatPack::AvatarGroup::Component) &&
        defined?(::FlatPack::Button::Component)
    end

    def recording_studio_accessible_avatar_items(recording, scope: :direct)
      management_path = recording_studio_accessible_access_management_path(recording)

      recording_studio_accessible_access_holders(recording, scope: scope).filter_map do |access_holder|
        avatar_item = RecordingStudioAccessible.configuration.avatar_for(access_holder)
        avatar_item&.merge(href: management_path)
      end
    end

    def recording_studio_accessible_access_holders(recording, scope: :direct)
      return [] unless recording

      access_recordings = recording_studio_accessible_access_recordings(recording, scope: scope)
      access_recordings = access_recordings.order(created_at: :asc, id: :asc) if access_recordings.respond_to?(:order)

      access_recordings.filter_map do |access_recording|
        access_recording.recordable&.actor
      end
    end

    def recording_studio_accessible_access_recordings(recording, scope: :direct)
      unless recording_studio_accessible_all_access_scope?(scope)
        return RecordingStudioAccessible.access_recordings_for(recording)
      end

      recording_studio_accessible_all_access_recordings(recording)
    end

    def recording_studio_accessible_all_access_scope?(scope)
      %w[all effective].include?(scope.to_s)
    end

    def recording_studio_accessible_all_access_recordings(recording)
      recordings = [recording]
      current_recording = recording.parent_recording

      while current_recording
        recordings << current_recording
        current_recording = current_recording.parent_recording
      end

      seen_actor_keys = {}

      recordings.each_with_object([]) do |current_scope_recording, access_recordings|
        direct_access_recordings = RecordingStudioAccessible::DirectAccessQuery.access_recordings_for(current_scope_recording)
        if direct_access_recordings.respond_to?(:order)
          direct_access_recordings = direct_access_recordings.order(created_at: :asc,
                                                                    id: :asc)
        end

        direct_access_recordings.each do |access_recording|
          actor = access_recording.recordable&.actor
          next unless actor

          actor_key = recording_studio_accessible_actor_key(actor)
          next if seen_actor_keys.key?(actor_key)

          seen_actor_keys[actor_key] = true
          access_recordings << access_recording
        end
      end
    end

    def recording_studio_accessible_actor_key(actor)
      actor_class = actor.class.respond_to?(:base_class) ? actor.class.base_class.name : actor.class.name
      actor_id = actor.respond_to?(:id) ? actor.id : actor.object_id

      [actor_class, actor_id]
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

    def recording_studio_accessible_access_button(recording, button_size:, button_style:)
      recording_studio_accessible_button(
        recording,
        text: "+ Access",
        button_size: button_size,
        button_style: button_style
      )
    end

    def recording_studio_accessible_manage_access_button(recording, button_size:, button_style:)
      button = recording_studio_accessible_button(
        recording,
        button_size: button_size,
        button_style: button_style,
        icon: "lock-closed",
        icon_only: true,
        aria: { label: "Manage access" }
      )

      return button unless defined?(::FlatPack::Tooltip::Component)

      render FlatPack::Tooltip::Component.new(text: "Manage access", placement: :top) do
        button
      end
    end

    def recording_studio_accessible_button(recording, button_size:, button_style:, text: nil, **)
      render FlatPack::Button::Component.new(
        text: text,
        style: button_style || :default,
        size: button_size,
        href: recording_studio_accessible_access_management_path(recording),
        **
      )
    end

    def recording_studio_accessible_avatar_actions(recording, avatar_items, size:, max:, overlap:, button_size:,
                                                   button_style:)
      content_tag(:div, class: "flex items-center justify-between gap-2") do
        safe_join(
          [
            render(recording_studio_accessible_avatar_group(recording, avatar_items, size: size, max: max,
                                                                                     overlap: overlap)),
            recording_studio_accessible_manage_access_button(recording, button_size: button_size,
                                                                        button_style: button_style)
          ]
        )
      end
    end

    def recording_studio_accessible_avatar_group(recording, avatar_items, size:, max:, overlap:)
      FlatPack::AvatarGroup::Component.new(
        items: avatar_items,
        max: max,
        size: size,
        overlap: overlap,
        show_tooltip: false,
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
