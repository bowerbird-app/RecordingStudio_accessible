# frozen_string_literal: true

module RecordingStudioAccessible
  class AccessRequestIndex
    PAGE_SIZE = 10
    FRAME_ID = "access_requests_index"
    STATUSES = %w[pending approved denied withdrawn all].freeze
    DEFAULT_STATUS = "pending"
    CURSOR_SQL = "(recording_studio_recordings.created_at, recording_studio_recordings.id) < (?, ?)"
    UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

    Page = Struct.new(:requests, :status, :next_cursor, :has_more, :multiple, :recording, keyword_init: true)

    class << self
      def page(recordings:, actor:, controller: nil, status: nil, cursor: nil)
        status = normalize_status(status)
        allowed = allowed_ids(recording_ids(recordings), actor, controller)
        rows = window(allowed, status, cursor)
        build_page(rows, status, allowed, recordings)
      end

      def filter_url(url, status)
        rewrite_url(url, "status" => status_param(status), "cursor" => nil)
      end

      def next_url(url, status, cursor)
        rewrite_url(url, "status" => status_param(status), "cursor" => cursor)
      end

      def cursor_for(request_recording)
        "#{request_recording.created_at.utc.iso8601(6)}|#{request_recording.id}"
      end

      def normalize_status(status)
        STATUSES.include?(status.to_s) ? status.to_s : DEFAULT_STATUS
      end

      private

      def recording_ids(recordings)
        return [] if recordings.blank?
        return [recordings.id] if recordings.is_a?(RecordingStudio::Recording)
        return recordings.pluck(:id) if recordings.respond_to?(:pluck)

        Array(recordings).map { |item| item.respond_to?(:id) ? item.id : item }
      end

      def allowed_ids(ids, actor, controller)
        return [] if ids.blank? || actor.blank?

        RecordingStudio::Recording.unscoped.where(id: ids).filter_map do |recording|
          recording.id if manageable?(recording, actor, controller)
        end
      end

      def manageable?(recording, actor, controller)
        AccessManagementPolicy.allowed?(recording: recording, actor: actor, controller: controller)
      end

      def window(parent_ids, status, cursor)
        scope = AccessRequestQuery.for_parents(parent_ids)
        scope = scope.where(recording_studio_access_requests: { status: status }) unless status == "all"
        older_than(scope, cursor).preload(:recordable, :parent_recording).limit(PAGE_SIZE + 1).to_a
      end

      def older_than(scope, cursor)
        time, id = decode_cursor(cursor)
        return scope unless time && id

        scope.where(CURSOR_SQL, time, id)
      end

      def decode_cursor(cursor)
        time_text, id = cursor.to_s.split("|", 2)
        return unless id.to_s.match?(UUID)

        [Time.zone.parse(time_text), id]
      rescue ArgumentError, TypeError
        nil
      end

      def build_page(rows, status, ids, recordings)
        visible = rows.first(PAGE_SIZE)
        Page.new(
          requests: visible, status: status, next_cursor: visible.last && cursor_for(visible.last),
          has_more: rows.size > PAGE_SIZE, multiple: ids.size > 1,
          recording: single_recording(recordings, ids)
        )
      end

      def single_recording(recordings, ids)
        return recordings if recordings.is_a?(RecordingStudio::Recording)
        return if ids.size != 1

        RecordingStudio::Recording.unscoped.find_by(id: ids.first)
      end

      def status_param(status)
        normalize_status(status) == DEFAULT_STATUS ? nil : normalize_status(status)
      end

      def rewrite_url(url, updates)
        uri = URI.parse(url.to_s)
        query = Rack::Utils.parse_query(uri.query)
        updates.each { |key, value| value.present? ? query[key] = value : query.delete(key) }
        uri.query = query.to_query.presence
        uri.to_s
      end
    end
  end
end
