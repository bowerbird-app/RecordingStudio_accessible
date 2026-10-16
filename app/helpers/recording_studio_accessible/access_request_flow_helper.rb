# frozen_string_literal: true

module RecordingStudioAccessible
  module AccessRequestFlowHelper
    def access_request_modal(recording, role: nil, action: nil, **options)
      render "recording_studio_accessible/access_requests/modal",
             **access_request_modal_locals(recording, role, action, options)
    end

    def access_request_t(key, **)
      access_request_copy_resolver.text(key, **)
    end

    def access_request_copy_fields
      resolver = access_request_copy_resolver
      fields = [hidden_field_tag(:copy_scope, resolver.scope)]
      resolver.overrides.each { |key, value| fields << hidden_field_tag("copy[#{key}]", value) }
      safe_join(fields)
    end

    def access_request_page_path(recording, role: nil, action: nil, **options)
      access_request_routes.new_recording_access_request_path(
        recording, **access_request_entry_params(role, action, options)
      )
    end

    def access_request_modal_src(recording, role: nil, action: nil, **options)
      access_request_routes.new_recording_access_request_path(
        recording, **access_request_entry_params(role, action, options, presentation: AccessRequestsHelper::MODAL)
      )
    end

    private

    def access_request_modal_locals(recording, role, action, options)
      copy = options[:copy]
      label = options[:label]
      {
        recording: recording, role: role, action: action, scope: options[:scope],
        copy: access_request_overrides(copy, label),
        label: access_request_cta(copy, label)
      }
    end

    def access_request_cta(copy, label)
      access_request_overrides(copy, label)["cta"].presence || accessible_t("requests.cta")
    end

    def access_request_overrides(copy, label)
      overrides = AccessRequestCopy.slice(copy)
      overrides["cta"] = label.to_s.strip if label.present?
      overrides
    end

    def access_request_entry_params(role, action, options, presentation: nil)
      copy = options[:copy]
      label = options[:label]
      {
        presentation: presentation, role: role, access_action: action,
        copy_scope: AccessRequestCopy.safe_scope(options[:scope]),
        copy: access_request_overrides(copy, label).presence
      }.compact
    end

    def access_request_copy_resolver
      AccessRequestCopy.resolve(session, @recording&.id, params)
    end
  end
end
