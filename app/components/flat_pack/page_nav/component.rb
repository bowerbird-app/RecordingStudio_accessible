# frozen_string_literal: true

module FlatPack
  module PageNav
    class Component < FlatPack::BaseComponent
      BACK_ACTION_DEFAULTS = {
        icon: "chevron-left",
        label: "Go back",
        style: :secondary,
        size: :md
      }.freeze

      ANCHOR_ACTION_DEFAULTS = {
        url: nil,
        icon: "x-mark",
        label: "Close",
        style: :secondary,
        size: :md
      }.freeze

      renders_one :right_slot

      def initialize(**system_arguments)
        @back_action = build_back_action(system_arguments)
        @anchor_action = build_anchor_action(system_arguments)

        super
      end

      def right(...)
        with_right_slot(...)
      end

      def right?
        right_slot?
      end

      def call
        content_tag(:nav, **nav_attributes) do
          content_tag(:div, class: "flex items-center justify-between gap-2") do
            safe_join([
              left_actions,
              right_action
            ].compact)
          end
        end
      end

      private

      def nav_attributes
        merge_attributes(
          class: classes("flat-pack-page-nav"),
          aria: { label: "Page navigation" },
          data: { controller: "flat-pack--page-nav" }
        )
      end

      def left_actions
        content_tag(:div, class: "flex items-center gap-2") do
          safe_join([
            back_action,
            anchor_action
          ].compact)
        end
      end

      def back_action
        icon_button(**@back_action, data: { action: "click->flat-pack--page-nav#back" })
      end

      def anchor_action
        return unless @anchor_action[:url].present?

        icon_button(**@anchor_action)
      end

      def right_action
        return unless right?

        right_slot.to_s
      end

      def icon_button(**options)
        button_arguments = {
          icon: options.fetch(:icon),
          icon_only: true,
          style: options.fetch(:style),
          size: options.fetch(:size),
          aria: { label: options.fetch(:label) }
        }
        button_arguments[:url] = options[:url] if options[:url].present?
        button_arguments[:data] = options[:data] if options[:data].present?

        render FlatPack::Button::Component.new(**button_arguments)
      end

      def build_back_action(system_arguments)
        BACK_ACTION_DEFAULTS.merge(
          icon: system_arguments.delete(:back_icon) || BACK_ACTION_DEFAULTS[:icon],
          label: system_arguments.delete(:back_label) || BACK_ACTION_DEFAULTS[:label],
          style: system_arguments.delete(:back_style) || BACK_ACTION_DEFAULTS[:style],
          size: system_arguments.delete(:back_size) || BACK_ACTION_DEFAULTS[:size]
        )
      end

      def build_anchor_action(system_arguments)
        ANCHOR_ACTION_DEFAULTS.merge(
          url: system_arguments.delete(:anchor_url),
          icon: system_arguments.delete(:anchor_icon) || ANCHOR_ACTION_DEFAULTS[:icon],
          label: system_arguments.delete(:anchor_label) || ANCHOR_ACTION_DEFAULTS[:label],
          style: system_arguments.delete(:anchor_style) || ANCHOR_ACTION_DEFAULTS[:style],
          size: system_arguments.delete(:anchor_size) || ANCHOR_ACTION_DEFAULTS[:size]
        )
      end
    end
  end
end
