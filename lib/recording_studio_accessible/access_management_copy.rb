# frozen_string_literal: true

module RecordingStudioAccessible
  class AccessManagementCopy
    KEYS = %w[
      manage.title
      form.new_title
      form.edit_title
      manage.add
      manage.add_access
      manage.empty_title
      manage.empty_subtitle
      requests.list_title
      manage.access_menu
    ].freeze

    def self.resolve(recording:, controller: nil)
      new(*parse(invoke(recording, controller)))
    end

    def self.slice(copy)
      raw = raw_copy(copy)
      raw.stringify_keys.slice(*KEYS).transform_values { |value| value.to_s.strip.first(200) }
    rescue StandardError
      {}
    end

    def self.safe_scope(scope)
      value = scope.to_s.strip
      return "" unless value.match?(/\A[a-z0-9_.]+\z/i)

      value
    end

    attr_reader :overrides, :scope

    def initialize(copy, scope)
      @overrides = copy
      @scope = scope.to_s
    end

    def text(key, **interpolations)
      interpolate(lookup(key.to_s, interpolations), interpolations)
    rescue StandardError
      Copy.t(key.to_s, **interpolations)
    end

    private

    def lookup(key, interpolations)
      override = overrides[key]
      return override if override.present?

      scoped = scoped_text(key)
      return scoped unless scoped.nil?

      Copy.t(key, **interpolations)
    end

    def scoped_text(key)
      return if @scope.blank?

      value = I18n.t("#{@scope}.#{key}", default: nil)
      value if value.is_a?(String)
    end

    def interpolate(value, interpolations)
      return value if interpolations.empty? || value.to_s.exclude?("%{")

      I18n.interpolate(value.to_s, interpolations)
    end

    class << self
      private

      def invoke(recording, controller)
        RecordingStudioAccessible.configuration.resolve_access_management_copy(
          recording: recording,
          controller: controller
        )
      end

      def parse(result)
        return [{}, ""] if result.nil?
        return [{}, ""] unless result.respond_to?(:to_h)

        hash = stringify(result)
        return [{}, ""] if hash.blank?

        [copy_from(hash), safe_scope(hash["scope"])]
      rescue StandardError
        [{}, ""]
      end

      def copy_from(hash)
        return slice(hash["copy"]) if hash.key?("copy")

        slice(hash)
      end

      def stringify(value)
        hash = value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value.to_h
        hash.respond_to?(:stringify_keys) ? hash.stringify_keys : hash.transform_keys(&:to_s)
      end

      def raw_copy(copy)
        return copy.permit(*KEYS).to_h if copy.respond_to?(:permit)
        return copy.to_h if copy.respond_to?(:to_h)

        {}
      end
    end
  end
end
