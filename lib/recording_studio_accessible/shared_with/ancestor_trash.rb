# frozen_string_literal: true

module RecordingStudioAccessible
  class SharedWith
    # Item ids that have a trashed ancestor. One query per tree level.
    class AncestorTrash
      MAX_DEPTH = 64

      def self.blocked_ids(items)
        new(items).blocked_ids
      end

      def initialize(items)
        @blocked = {}
        @owners = {}
        items.each { |item| track(item) }
      end

      def blocked_ids
        MAX_DEPTH.times do
          break if @owners.empty?

          step
        end
        @owners.each_value { |ids| block(ids) }
        @blocked
      end

      private

      def track(item)
        parent_id = item.parent_recording_id
        return if parent_id.blank?

        (@owners[parent_id] ||= []) << item.id
      end

      def step
        rows = load(@owners.keys)
        next_owners = {}
        @owners.each { |ancestor_id, item_ids| follow(ancestor_id, item_ids, rows, next_owners) }
        @owners = next_owners
      end

      def load(ids)
        RecordingStudio::Recording.unscoped.where(id: ids).pluck(:id, :parent_recording_id, :trashed_at)
                                  .to_h { |id, parent_id, trashed_at| [id, [parent_id, trashed_at.present?]] }
      end

      def follow(ancestor_id, item_ids, rows, next_owners)
        row = rows[ancestor_id]
        return block(item_ids) if row.nil? || row.last

        parent_id = row.first
        return if parent_id.blank?

        (next_owners[parent_id] ||= []).concat(item_ids)
      end

      def block(item_ids)
        item_ids.each { |item_id| @blocked[item_id] = true }
      end
    end
  end
end
