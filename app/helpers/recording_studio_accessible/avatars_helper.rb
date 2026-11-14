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

    def recording_studio_accessible_access_menu_item(recording, dropdown, label: Copy::UNSET, scope: :direct)
      return unless recording_studio_accessible_access_menu_available?(dropdown)
      return unless recording
      return unless recording_studio_accessible_manage_access?(recording)

      path = recording_studio_accessible_access_management_path(recording)
      return if path.blank?

      dropdown.menu_item(
        text: recording_studio_accessible_access_menu_label(label, recording),
        href: path,
        badge: recording_studio_accessible_access_holders(recording, scope: scope).size.to_s
      )
    end

    private

    def recording_studio_accessible_flatpack_available?
      defined?(::FlatPack::AvatarGroup::Component) &&
        defined?(::FlatPack::Button::Component)
    end

    def recording_studio_accessible_access_menu_available?(dropdown)
      defined?(::FlatPack::Button::Dropdown::Component) && dropdown.respond_to?(:menu_item)
    end

    def recording_studio_accessible_access_menu_label(label, recording)
      if Copy.provided?(label)
        text = label.to_s.strip
        return text if text.present?
      end

      AccessManagementCopy.resolve(recording: recording, controller: self).text("manage.access_menu")
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
      access_recordings = recording_studio_accessible_ordered_grants(access_recordings)

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
      recordings = recording_studio_accessible_recording_chain(recording)
      grants_by_parent = recording_studio_accessible_grants_by_parent(recordings)
      seen_actor_keys = {}

      recordings.each_with_object([]) do |current_scope_recording, access_recordings|
        parent_id = current_scope_recording.respond_to?(:id) ? current_scope_recording.id : current_scope_recording
        Array(grants_by_parent[parent_id]).each do |access_recording|
          actor = access_recording.recordable&.actor
          next unless actor

          actor_key = recording_studio_accessible_actor_key(actor)
          next if seen_actor_keys.key?(actor_key)

          seen_actor_keys[actor_key] = true
          access_recordings << access_recording
        end
      end
    end

    def recording_studio_accessible_recording_chain(recording)
      recordings = []
      seen_ids = {}
      current_recording = recording

      while current_recording
        marker = current_recording.respond_to?(:id) ? current_recording.id : current_recording.object_id
        break if seen_ids[marker]

        seen_ids[marker] = true
        recordings << current_recording
        current_recording = current_recording.parent_recording
      end

      recordings
    end

    def recording_studio_accessible_grants_by_parent(recordings)
      loaded = RecordingStudioAccessible::DirectAccessQuery.access_recordings_for_parents(recordings)
      loaded = recording_studio_accessible_preload_grant_actors(loaded)
      loaded = loaded.order(created_at: :asc, id: :asc) if loaded.respond_to?(:order)
      grants = loaded.sort_by { |grant| [grant.created_at, grant.id.to_s] }
      grants.group_by(&:parent_recording_id)
    end

    def recording_studio_accessible_ordered_grants(access_recordings)
      access_recordings = recording_studio_accessible_preload_grant_actors(access_recordings)
      return access_recordings.order(created_at: :asc, id: :asc) if access_recordings.respond_to?(:order)

      access_recordings
    end

    def recording_studio_accessible_preload_grant_actors(access_recordings)
      return access_recordings unless access_recordings.respond_to?(:preload)

      access_recordings.preload(recordable: :actor)
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
        text: AccessManagementCopy.resolve(recording: recording, controller: self).text("manage.add_access"),
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
        aria: { label: Copy.t("manage.manage_access") }
      )

      return button unless defined?(::FlatPack::Tooltip::Component)

      render FlatPack::Tooltip::Component.new(text: Copy.t("manage.manage_access"), placement: :top) do
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
