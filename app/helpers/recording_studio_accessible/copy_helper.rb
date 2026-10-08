# frozen_string_literal: true

module RecordingStudioAccessible
  module CopyHelper
    def accessible_t(...)
      Copy.t(...)
    end

    def accessible_copy(override, key, **)
      Copy.value(override, key, **)
    end

    def accessible_role_name(role)
      Copy.role_name(role)
    end

    def accessible_invitation_state(state)
      Copy.invitation_state(state)
    end

    def accessible_document_attributes(extra = {})
      attributes = { lang: I18n.locale.to_s }.merge(extra)
      attributes.merge!(recording_studio_locale_attributes) if respond_to?(:recording_studio_locale_attributes)
      return attributes unless respond_to?(:flat_pack_copy_data)

      attributes[:data] = (attributes[:data] || {}).merge(flat_pack_copy_data)
      attributes
    end
  end
end
