module ApplicationHelper
  include DummyLayoutHelper

  def append_recording_tree_nodes(tree, nodes)
    Array(nodes).each do |node|
      recording = node.fetch(:recording)
      children = Array(node.fetch(:children))
      args = {
        label: recording_tree_label(recording),
        expanded: children.any?,
        meta: recording_tree_meta(recording, children.size)
      }

      if children.any?
        tree.node(**args) { |child_tree| append_recording_tree_nodes(child_tree, children) }
      else
        tree.node(**args)
      end
    end
  end

  def recording_tree_label(recording)
    recordable = recording.recordable
    kind = recording_tree_kind(recording)
    return "Missing #{kind}" if recordable.nil?
    return recording_tree_access_label(recordable) if recordable.is_a?(RecordingStudio::Access)

    recordable.try(:name).presence || recordable.try(:title).presence || kind
  end

  def recording_tree_meta(recording, children_count)
    parts = [recording_tree_kind(recording), recording_tree_children_label(children_count), "ID #{recording.id}"]
    parts.join(" · ")
  end

  private

  def recording_tree_kind(recording)
    recording.recordable_type.to_s.demodulize
  end

  def recording_tree_children_label(children_count)
    return "Leaf" if children_count.zero?
    return "1 child" if children_count == 1

    "#{children_count} children"
  end

  def recording_tree_access_label(access)
    actor = access.actor
    actor_label = actor&.try(:email).presence || actor&.try(:name).presence || "Unknown actor"
    "#{access.role} access for #{actor_label}"
  end
end
