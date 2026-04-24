# frozen_string_literal: true

module RecordingStudioAccessible
  module RecordingAccessesHelper
    ROLE_OPTIONS = [%w[View view], %w[Edit edit], %w[Admin admin]].freeze

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
                      edit_recording_access_path(recording, row[:id]),
                      class: "text-[var(--link-color,var(--surface-content-color))] underline-offset-2 hover:underline"
                    ),
                    button_to(
                      "Delete",
                      recording_access_path(recording, row[:id]),
                      method: :delete,
                      form_class: "inline",
                      class: "cursor-pointer text-[var(--danger-text-color,var(--surface-content-color))] underline-offset-2 hover:underline"
                    )
                  ])
      end
    end

    private

    def access_role_label(role)
      role.to_s.humanize
    end
  end
end
