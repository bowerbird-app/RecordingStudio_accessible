# frozen_string_literal: true

module RecordingStudioAccessible
  module RecordingAccessesHelper
    ROLE_OPTIONS = [%w[View view], %w[Edit edit], %w[Admin admin]].freeze

    def recording_access_index_back_url
      params[:back_url].presence || host_root_path
    end

    def recording_access_anchor_url
      params[:anchor_url].presence || recording_access_index_back_url
    end

    def recording_access_index_path_with_back_url(recording)
      recording_accesses_path(recording, **recording_access_navigation_params(back_url: recording_access_index_back_url))
    end

    def new_recording_access_path_with_back_url(recording)
      new_recording_access_path(recording, **recording_access_navigation_params(back_url: recording_access_index_back_reference(recording)))
    end

    def edit_recording_access_path_with_back_url(recording, access_id)
      edit_recording_access_path(recording, access_id, **recording_access_navigation_params(back_url: recording_access_index_back_reference(recording)))
    end

    def recording_access_collection_path_with_navigation(recording)
      recording_accesses_path(recording, **recording_access_navigation_params)
    end

    def recording_access_path_with_navigation(recording, access_id)
      recording_access_path(recording, access_id, **recording_access_navigation_params)
    end

    def access_role_options
      ROLE_OPTIONS
    end

    def access_person_cell(row)
      content_tag(:span, row[:actor_label], class: "font-medium text-[var(--surface-content-color)]")
    end

    def access_actor_type_cell(row)
      content_tag(:span, row[:actor_type], class: "text-sm text-[var(--surface-content-color)]")
    end

    def access_role_cell(row)
      content_tag(:span, access_role_label(row[:direct_role]), class: "text-sm text-[var(--surface-content-color)]")
    end

    def inherited_access_source_cell(row)
      content_tag(:span, row[:source_label], class: "text-sm text-[var(--surface-content-color)]")
    end

    def inherited_access_source_role_cell(row)
      content_tag(:span, access_role_label(row[:source_role]), class: "text-sm text-[var(--surface-content-color)]")
    end

    def access_actions_cell(recording, row)
      content_tag(:div, class: "flex items-center gap-3 text-sm") do
        safe_join([
                    link_to(
                      "Edit",
                      edit_recording_access_path_with_back_url(recording, row[:id]),
                      class: "text-[var(--link-color,var(--surface-content-color))] underline-offset-2 hover:underline"
                    ),
                    button_to(
                      "Delete",
                      recording_access_path_with_navigation(recording, row[:id]),
                      method: :delete,
                      form_class: "inline",
                      class: "cursor-pointer text-[var(--danger-text-color,var(--surface-content-color))] underline-offset-2 hover:underline"
                    )
                  ])
      end
    end

    private

    def recording_access_index_back_reference(recording)
      recording_accesses_path(recording, **recording_access_navigation_params(back_url: recording_access_index_back_url))
    end

    def recording_access_navigation_params(back_url: params[:back_url].presence)
      navigation_params = { anchor_url: recording_access_anchor_url }
      navigation_params[:back_url] = back_url if back_url.present?
      navigation_params
    end

    def host_root_path
      return main_app.root_path if respond_to?(:main_app) && main_app.respond_to?(:root_path)

      "/"
    end

    def access_role_label(role)
      role.to_s.humanize
    end
  end
end
