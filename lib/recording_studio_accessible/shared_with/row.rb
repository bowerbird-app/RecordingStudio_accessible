# frozen_string_literal: true

module RecordingStudioAccessible
  class SharedWith
    class Row
      def self.from(grant, blocked:)
        new(grant, blocked).item
      end

      def initialize(grant, blocked)
        @grant = grant
        @blocked = blocked
      end

      def item
        return if blocked[grant.parent_recording_id]
        return unless shareable?

        resolved = resolve(grant.parent_recording)
        return unless resolved

        build(resolved)
      end

      private

      attr_reader :grant, :blocked

      def shareable?
        return false unless DependentAccess.effective?(grant)
        return false if grant.trashed_at.present?

        recording = grant.parent_recording
        recording && recording.trashed_at.blank? && recording.parent_recording_id.present?
      end

      def build(resolved)
        role = grant.recordable&.role.to_s
        return if role.blank?

        root = grant.root_recording
        Item.new(
          recording: grant.parent_recording, role: role, root: root,
          title: resolved[:title], url: resolved[:url], workspace: workspace_name(root),
          role_label: Copy.role_name(role), cursor: SharedWith.cursor_for(grant)
        )
      end

      def resolve(recording)
        callable = RecordingStudioAccessible.configuration.shared_item_resolver
        return unless callable.respond_to?(:call)

        title_and_url(call_resolver(callable, recording))
      rescue StandardError
        nil
      end

      def call_resolver(callable, recording)
        if callable.parameters.any? { |type, _name| %i[key keyreq keyrest].include?(type) }
          callable.call(recording: recording)
        else
          callable.call(recording)
        end
      end

      def title_and_url(result)
        title, url = read_title_and_url(result)
        return if title.blank? || url.blank?

        { title: title.to_s, url: url.to_s }
      end

      def read_title_and_url(result)
        return if result.nil?
        return hash_title_and_url(result) if result.is_a?(Hash)
        return unless result.respond_to?(:title) && result.respond_to?(:url)

        [result.title, result.url]
      end

      def hash_title_and_url(result)
        [result[:title] || result["title"], result[:url] || result["url"]]
      end

      def workspace_name(root)
        label = recordable_label(root&.recordable)
        label.presence || Copy.t("shared_with.workspace_fallback")
      end

      def recordable_label(recordable)
        return if recordable.nil?

        %i[name title].each do |method_name|
          next unless recordable.respond_to?(method_name)

          value = recordable.public_send(method_name)
          return value if value.present?
        end
        nil
      end
    end
  end
end
