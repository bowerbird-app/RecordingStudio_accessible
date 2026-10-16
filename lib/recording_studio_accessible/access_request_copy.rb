# frozen_string_literal: true

module RecordingStudioAccessible
  class AccessRequestCopy
    SESSION_KEY = :recording_studio_accessible_access_request_copy
    KEYS = %w[
      cta email_title name email_label email_submit verify_title verify_intro
      code confirm resend form_title message submit sent_title sent_body
      page_link already flashes.submitted flashes.code_resent
    ].freeze

    def self.remember(session, recording_id, params)
      return unless params.key?(:copy) || params.key?(:copy_scope)

      session[SESSION_KEY] = {
        "recording_id" => recording_id.to_s,
        "copy" => slice(params[:copy]),
        "scope" => safe_scope(params[:copy_scope])
      }
    end

    def self.resolve(session, recording_id, params)
      stored = stored_for(session, recording_id)
      new(merged_copy(stored, params), merged_scope(stored, params))
    end

    def self.slice(copy)
      raw = raw_copy(copy)
      raw.stringify_keys.slice(*KEYS).transform_values { |value| value.to_s.strip.first(200) }
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
    end

    private

    def lookup(key, interpolations)
      override = overrides[key]
      return override if override.present?

      scoped = scoped_text(key)
      return scoped unless scoped.nil?

      Copy.t("requests.#{key}", **interpolations)
    end

    def scoped_text(key)
      return if @scope.blank?

      I18n.t("#{@scope}.#{key}", default: nil)
    end

    def interpolate(value, interpolations)
      return value if interpolations.empty? || value.to_s.exclude?("%{")

      I18n.interpolate(value.to_s, interpolations)
    end

    class << self
      private

      def stored_for(session, recording_id)
        stored = session[SESSION_KEY]
        return unless stored.is_a?(Hash) && stored["recording_id"] == recording_id.to_s

        stored
      end

      def merged_copy(stored, params)
        return slice(params[:copy]) if params.key?(:copy)

        stored&.fetch("copy", {}) || {}
      end

      def merged_scope(stored, params)
        return safe_scope(params[:copy_scope]) if params.key?(:copy_scope)

        stored&.fetch("scope", "").to_s
      end

      def raw_copy(copy)
        return copy.permit(*KEYS).to_h if copy.respond_to?(:permit)
        return copy.to_h if copy.respond_to?(:to_h)

        {}
      end
    end
  end
end
