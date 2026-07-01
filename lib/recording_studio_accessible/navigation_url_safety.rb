# frozen_string_literal: true

require "uri"

module RecordingStudioAccessible
  module NavigationUrlSafety
    private

    # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    def safe_local_navigation_url(value, fallback:)
      fallback_value = fallback.presence || "/"
      candidate = value.to_s.strip
      return fallback_value if candidate.blank?
      return fallback_value if candidate.match?(/[\u0000-\u001f\u007f\\]/)
      return fallback_value unless candidate.start_with?("/")
      return fallback_value if candidate.start_with?("//")

      uri = URI.parse(candidate)
      return fallback_value if uri.scheme.present? || uri.host.present?

      candidate
    rescue URI::InvalidURIError
      fallback_value
    end
    # rubocop:enable Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  end
end
