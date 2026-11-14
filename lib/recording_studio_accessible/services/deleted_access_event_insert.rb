# frozen_string_literal: true

module RecordingStudioAccessible
  module Services
    # Inserts a planned batch of deleted access events and notifies listeners.
    class DeletedAccessEventInsert
      def self.insert!(plans)
        new(plans).insert!
      end

      def initialize(plans)
        @plans = plans
      end

      def insert!
        base = Time.current
        rows = @plans.each_with_index.map { |plan, index| row_for(plan, base + (index * 0.000001)) }
        result = RecordingStudio::Event.insert_all!(rows, returning: %w[id])
        publish(result.rows.map(&:first))
        schedule_counters!(rows)
      end

      private

      def publish(ids)
        events = RecordingStudio::Event.where(id: ids).index_by { |event| event.id.to_s }
        ids.each do |id|
          event = events.fetch(id.to_s)
          RecordingStudio.send(:instrument_event, event)
          RecordingStudio::Hooks.run(:after_record, event)
        end
      end

      def row_for(plan, stamp)
        recordable_type, recordable_id = pair(plan[:recordable])
        actor_type, actor_id = pair(plan[:actor])
        impersonator_type, impersonator_id = pair(plan[:impersonator])

        {
          action: "deleted",
          recording_id: plan[:target].id,
          recordable_type: recordable_type,
          recordable_id: recordable_id,
          previous_recordable_type: recordable_type,
          previous_recordable_id: recordable_id,
          actor_type: actor_type,
          actor_id: actor_id,
          impersonator_type: impersonator_type,
          impersonator_id: impersonator_id,
          metadata: plan[:metadata],
          occurred_at: stamp,
          created_at: stamp,
          idempotency_key: nil
        }
      end

      def pair(record)
        return [nil, nil] unless record

        [record.class.polymorphic_name, record.id]
      end

      def schedule_counters!(rows)
        counts = rows.group_by { |row| [row[:recordable_type], row[:recordable_id]] }
        RecordingStudio::Recording.connection.current_transaction.after_commit do
          counts.each do |(recordable_type, recordable_id), group|
            RecordingStudio.update_polymorphic_counter(recordable_type, recordable_id, :events_count, group.size)
          end
        end
      end
    end
  end
end
