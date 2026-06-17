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

    def show_access_actor_type_column?(direct_rows, inherited_rows = [])
      actor_types = (Array(direct_rows) + Array(inherited_rows))
                    .map { |row| row[:actor_type].to_s.strip }
                    .reject(&:empty?)
                    .uniq

      actor_types.size > 1
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

    def inherited_access_actions_cell(recording, row)
      source_recording = row[:source_recording]
      return content_tag(:span, "-", class: "text-sm text-[var(--surface-content-color)]") unless source_recording

      render FlatPack::Button::Dropdown::Component.new(
        text: "",
        style: :ghost,
        icon: "ellipsis-vertical",
        show_chevron: false,
        trigger_attributes: {
          title: "Access point actions",
          aria: { label: "Access point actions" }
        }
      ) do |dropdown|
        dropdown.menu_item(
          text: "Manage access",
          href: recording_accesses_path(
            source_recording,
            **recording_access_navigation_params(back_url: recording_access_index_back_reference(recording))
          )
        )
      end
    end

    def access_actions_cell(recording, row)
      delete_form_id = "remove-access-form-#{row[:id]}"

      dropdown = render FlatPack::Button::Dropdown::Component.new(
        text: "",
        style: :ghost,
        icon: "ellipsis-vertical",
        show_chevron: false,
        trigger_attributes: {
          title: "Access actions",
          aria: { label: "Access actions" }
        }
      ) do |dropdown|
        dropdown.menu_item(
          text: "Edit",
          href: edit_recording_access_path_with_back_url(recording, row[:id])
        )
        dropdown.menu_item(
          text: "Remove access",
          destructive: true,
          form: delete_form_id,
          type: :submit
        )
      end

      delete_form = form_with(
        url: recording_access_path_with_navigation(recording, row[:id]),
        method: :delete,
        local: true,
        html: { id: delete_form_id, class: "hidden" }
      ) { "" }

      safe_join([dropdown, delete_form])
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
