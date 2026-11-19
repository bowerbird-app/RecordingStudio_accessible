# frozen_string_literal: true

require "uri"

module RecordingStudioAccessible
  # Direct item grants for one actor, across every root.
  # A grant whose parent is a root is workspace access and hides that root.
  class SharedWith
    PAGE_SIZE = 10
    BATCH = PAGE_SIZE + 1
    FRAME_ID = "shared_with_index"
    UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

    Item = Struct.new(
      :recording, :role, :root, :title, :url, :workspace, :role_label, :cursor,
      keyword_init: true
    )
    Page = Struct.new(:items, :next_cursor, :has_more, keyword_init: true)
    class InvalidCursor < ArgumentError; end

    class << self
      def page(actor:, cursor: nil)
        new(actor: actor, cursor: cursor).page
      end

      def next_url(url, cursor)
        uri = URI.parse(url.to_s)
        query = Rack::Utils.parse_query(uri.query)
        cursor.present? ? query["cursor"] = cursor : query.delete("cursor")
        uri.query = query.to_query.presence
        uri.to_s
      end

      def cursor_for(grant)
        "#{grant.created_at.utc.iso8601(6)}|#{grant.id}"
      end
    end

    def initialize(actor:, cursor:)
      @actor = actor
      @cursor = cursor
    end

    def page
      return empty_page if actor.nil?

      validate_actor!
      point = decode_cursor
      return empty_page unless resolver?

      collect(point)
    end

    private

    attr_reader :actor, :cursor

    def collect(point)
      visible = []
      loop do
        rows = grants.window(point)
        return finish(visible, false) if rows.empty?

        point, done = consume(rows, visible, point)
        return done if done
        return finish(visible, false) if rows.size < BATCH
      end
    end

    def grants
      @grants ||= Query.new(actor)
    end

    def consume(rows, visible, point)
      blocked = AncestorTrash.blocked_ids(rows.filter_map(&:parent_recording))
      rows.each do |grant|
        point = [grant.created_at, grant.id]
        item = Row.from(grant, blocked: blocked)
        next unless item
        return [point, finish(visible, true)] if visible.size == PAGE_SIZE

        visible << item
      end
      [point, nil]
    end

    def resolver?
      RecordingStudioAccessible.configuration.shared_item_resolver.respond_to?(:call)
    end

    def validate_actor!
      raise ArgumentError, "unsupported actor type" unless supported_actor?

      raise ArgumentError, "unsupported actor type" if ActorType.for(actor).blank?
    rescue NoMethodError
      raise ArgumentError, "unsupported actor type"
    end

    def supported_actor?
      actor.respond_to?(:id) && actor.class.respond_to?(:base_class)
    end

    def decode_cursor
      return if cursor.blank?

      time, id = cursor_parts
      raise InvalidCursor if time.nil?

      [time, id]
    end

    def cursor_parts
      time_text, id = cursor.to_s.split("|", 2)
      raise InvalidCursor unless id.to_s.match?(UUID)

      [Time.zone.parse(time_text), id]
    rescue ArgumentError, TypeError
      raise InvalidCursor
    end

    def empty_page
      finish([], false)
    end

    def finish(items, has_more)
      Page.new(items: items, next_cursor: items.last&.cursor, has_more: has_more)
    end
  end
end

require_relative "shared_with/ancestor_trash"
require_relative "shared_with/query"
require_relative "shared_with/row"
