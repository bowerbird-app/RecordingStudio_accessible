# frozen_string_literal: true

module RecordingStudioAccessible
  # Flat snapshot stored on an access request. Bad entries are dropped and reported.
  module AccessRequestGateMetadata
    KEY = /\A[a-z0-9_]{1,40}\z/
    MAX_KEYS = 32
    MAX_STRING = 200
    MAX_BYTES = 2_048
    INVALID = Object.new.freeze
    SCALAR_CLASSES = [NilClass, TrueClass, FalseClass, Integer].freeze

    class << self
      def clean(raw)
        return {} if raw.blank?
        return reject("expected a hash") unless raw.is_a?(Hash)

        cleaned, dropped = collect(raw)
        dropped = true if trim!(cleaned)
        report("invalid entries removed") if dropped
        cleaned
      end

      private

      def reject(detail)
        report(detail)
        {}
      end

      def collect(raw)
        cleaned = {}
        dropped = false
        raw.each do |key, value|
          dropped = true if store(cleaned, key, value) == :dropped
        end
        [cleaned, dropped]
      end

      def store(cleaned, key, value)
        normalized = key_for(key)
        scalar = value_for(value)
        return :dropped unless keep?(cleaned, normalized, scalar)

        cleaned[normalized] = scalar
        :kept
      end

      def keep?(cleaned, key, value)
        return false if key.nil? || value.equal?(INVALID)
        return false if !cleaned.key?(key) && cleaned.size >= MAX_KEYS

        true
      end

      def trim!(cleaned)
        return unless json_bytes(cleaned) > MAX_BYTES

        cleaned.delete(cleaned.keys.last) while over_limit?(cleaned)
        :trimmed
      end

      def over_limit?(cleaned)
        cleaned.any? && json_bytes(cleaned) > MAX_BYTES
      end

      def key_for(key)
        text = key.is_a?(Symbol) ? key.name : key
        return unless text.is_a?(String) && KEY.match?(text)

        text
      end

      def value_for(value)
        return string_value(value) if value.is_a?(String)
        return float_value(value) if value.is_a?(Float)
        return value if SCALAR_CLASSES.include?(value.class)

        INVALID
      end

      def float_value(value)
        value.finite? ? value : INVALID
      end

      def string_value(value)
        return INVALID if value.length > MAX_STRING || !value.valid_encoding?

        value
      end

      def json_bytes(hash)
        ActiveSupport::JSON.encode(hash).bytesize
      end

      def report(detail)
        message = "[RecordingStudioAccessible] access request gate metadata dropped: #{detail}"
        Rails.logger.warn(message) if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        return unless defined?(Rails.error) && Rails.error.respond_to?(:report)

        Rails.error.report(error_for(message), handled: true, source: "recording_studio_accessible")
      rescue StandardError
        nil
      end

      def error_for(message)
        RecordingStudioAccessible::Error.new(message)
      end
    end
  end
end
