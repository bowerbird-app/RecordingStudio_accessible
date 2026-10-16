# frozen_string_literal: true

require "uri"

module RecordingStudioAccessible
  # Continuation targets stay on the request host. Relative paths count as this host.
  module AccessRequestContinuation
    class << self
      def location(url, request:, carry:)
        safe = same_host(url, request)
        return if safe.blank?

        with_query(safe, carry)
      end

      private

      def same_host(url, request)
        candidate = url.to_s.strip
        return if candidate.blank? || candidate.match?(/[\u0000-\u001f\u007f\\]/)
        return candidate if local_path?(candidate)

        absolute_match(candidate, request)
      end

      def local_path?(candidate)
        return false unless candidate.start_with?("/") && !candidate.start_with?("//")

        uri = URI.parse(candidate)
        uri.scheme.nil? && uri.host.nil?
      rescue URI::InvalidURIError
        false
      end

      def absolute_match(candidate, request)
        uri = URI.parse(candidate)
        return unless http?(uri) && same_endpoint?(uri, request)

        uri.to_s
      rescue URI::InvalidURIError
        nil
      end

      def http?(uri)
        uri.is_a?(URI::HTTP) && uri.host.present?
      end

      def same_endpoint?(uri, request)
        uri.host.casecmp?(request.host.to_s) && uri.port == request.port
      end

      def with_query(url, carry)
        uri = URI.parse(url)
        params = Rack::Utils.parse_query(uri.query.to_s)
        Array(carry).each { |key, value| assign_param(params, key, value) }
        uri.query = params.to_query.presence
        uri.to_s
      end

      def assign_param(params, key, value)
        return if value.blank?
        return if params.key?(key.to_s) && key.to_s != "presentation"

        params[key.to_s] = value.to_s
      end
    end
  end
end
