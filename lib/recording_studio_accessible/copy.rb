# frozen_string_literal: true

require "i18n"
require_relative "translation"

module RecordingStudioAccessible
  module Copy
    PREFIX = Translation::PREFIX
    UNSET = Object.new.freeze

    module_function

    def t(key, **)
      Translation.t("#{PREFIX}.#{key}", **)
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
      return name if name.empty?

      t("roles.#{name}", default: name.humanize)
    end

    def invitation_state(state)
      name = state.to_s
      t("invitations.states.#{name}", default: name)
    end
  end
end
