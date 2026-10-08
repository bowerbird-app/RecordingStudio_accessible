# frozen_string_literal: true

require "erb"
require "i18n"

module RecordingStudioAccessible
  module Copy
    PREFIX = "recording_studio.accessible"
    UNSET = Object.new.freeze

    module_function

    def t(key, **options)
      full_key = "#{PREFIX}.#{key}"
      return I18n.t(full_key, **options) unless key.to_s.end_with?("_html")

      escaped = options.transform_values { |value| value.is_a?(String) ? ERB::Util.html_escape(value) : value }
      I18n.t(full_key, **escaped).to_s.html_safe
    end

    def l(object, **)
      I18n.l(object, **)
    end

    def provided?(value)
      !value.equal?(UNSET)
    end

    def value(override, key, **)
      provided?(override) ? override : t(key, **)
    end

    # Host config that still matches the English default follows the locale.
    # A different string (including blank after presence) is host copy and wins.
    def defaulted(value, default, key, **)
      return t(key, **) if value.nil? || value == default

      value
    end

    def role_name(role)
      name = role.to_s
      t("roles.#{name}", default: name.humanize)
    end

    def invitation_state(state)
      name = state.to_s
      t("invitations.states.#{name}", default: name)
    end
  end
end
