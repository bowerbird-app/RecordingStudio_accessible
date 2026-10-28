# frozen_string_literal: true

module RecordingStudioAccessible
  class Configuration
    module Avatars
      def avatar_for(access_holder)
        normalize_avatar(resolve_configurable(avatar_resolver, access_holder))
      end

      private

      def assign_avatar_defaults
        @avatar_resolver = method(:default_avatar_resolver)
      end

      def default_avatar_resolver(_access_holder)
        nil
      end

      def normalize_avatar(avatar)
        return unless avatar.respond_to?(:to_h)

        attributes = avatar.to_h.symbolize_keys
        normalized = compact_avatar_attributes(attributes)
        normalized if normalized.values.any?(&:present?)
      end

      def compact_avatar_attributes(attributes)
        {
          name: attributes[:name],
          alt: attributes[:alt],
          src: safe_avatar_image_url(attributes[:src] || attributes[:image_url]),
          status: attributes[:status],
          href: safe_avatar_href(attributes[:href])
        }.compact
      end

      def safe_avatar_image_url(url)
        safe_avatar_url(url, allow_absolute_http: true)
      end

      def safe_avatar_href(url)
        safe_avatar_url(url, allow_absolute_http: false)
      end

      def safe_avatar_url(url, allow_absolute_http:)
        value = url.to_s.strip
        return if value.blank? || value.match?(/[\u0000-\u001f\u007f\\]/)
        return value if relative_avatar_url?(value)

        parsed_http_avatar_url(value, allow_absolute_http: allow_absolute_http)
      end

      def parsed_http_avatar_url(value, allow_absolute_http:)
        uri = URI.parse(value)
        value if allow_absolute_http && uri.is_a?(URI::HTTP) && uri.host.present?
      rescue URI::InvalidURIError
        nil
      end

      def relative_avatar_url?(url)
        url.start_with?("/") && !url.start_with?("//")
      end
    end
  end
end
