# frozen_string_literal: true

module FlatPack
  module Tree
    class Component < FlatPack::BaseComponent
      def initialize(nodes:, **system_arguments)
        @nodes = Array(nodes)
        super(**system_arguments)
      end

      def call
        content_tag(:div, **wrapper_attributes) do
          return empty_state if @nodes.empty?

          render_nodes(@nodes, depth: 1)
        end
      end

      private

      def wrapper_attributes
        merge_attributes(class: "rounded-xl border border-slate-200 bg-white p-4")
      end

      def empty_state
        content_tag(:p, "No recordings were found.", class: "text-sm text-slate-600")
      end

      def render_nodes(nodes, depth:)
        content_tag(:ul, class: list_classes(depth), role: depth == 1 ? "tree" : "group") do
          safe_join(nodes.map { |node| render_node(node, depth: depth) })
        end
      end

      def render_node(node, depth:)
        recording = node.fetch(:recording)
        children = Array(node.fetch(:children))

        content_tag(:li, role: "treeitem", aria: { level: depth, expanded: children.any? }) do
          safe_join([
            node_header(recording: recording, children_count: children.size),
            children.any? ? render_nodes(children, depth: depth + 1) : nil
          ].compact)
        end
      end

      def list_classes(depth)
        base_classes = ["space-y-2"]
        base_classes << "ms-6 border-s border-slate-200 ps-4" if depth > 1
        classes(*base_classes)
      end

      def node_header(recording:, children_count:)
        content_tag(:div, class: "flex flex-wrap items-center gap-2 rounded-md px-1 py-1") do
          safe_join([
            render(FlatPack::Badge::Component.new(text: recordable_kind(recording), style: :default, size: :sm)),
            content_tag(:span, recordable_label(recording), class: "text-sm font-medium text-slate-900"),
            render(FlatPack::Chip::Component.new(text: children_count_label(children_count), style: :default, size: :sm)),
            content_tag(:span, "ID #{recording.id}", class: "text-xs text-slate-500")
          ])
        end
      end

      def children_count_label(children_count)
        return "Leaf" if children_count.zero?

        children_count == 1 ? "1 child" : "#{children_count} children"
      end

      def recordable_kind(recording)
        recording.recordable_type.to_s.demodulize
      end

      def recordable_label(recording)
        recordable = recording.recordable
        return "Missing #{recordable_kind(recording)}" if recordable.nil?

        return access_label(recordable) if recordable.is_a?(RecordingStudio::Access)

        recordable.try(:name).presence || recordable.try(:title).presence || recordable_kind(recording)
      end

      def access_label(access)
        actor = access.actor
        actor_label = actor&.try(:email).presence || actor&.try(:name).presence || "Unknown actor"
        "#{access.role} access for #{actor_label}"
      end
    end
  end
end
