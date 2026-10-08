# frozen_string_literal: true

module RecordingStudioAccessible
  module RecordingAccessesHelper
    include RecordingStudioAccessible::NavigationUrlSafety
    include RecordingStudioAccessible::CopyHelper

    def recording_access_index_back_url
      safe_local_navigation_url(params[:back_url], fallback: host_root_path)
    end

    def recording_access_anchor_url
      safe_local_navigation_url(params[:anchor_url], fallback: recording_access_index_back_url)
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

    def access_role_options(recording = nil)
      RecordingStudioAccessible.roles_for(recording).map { |name| [accessible_role_name(name), name] }
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
          title: accessible_t("manage.access_point_actions"),
          aria: { label: accessible_t("manage.access_point_actions") }
        }
      ) do |dropdown|
        dropdown.menu_item(
          text: accessible_t("manage.manage_access"),
          href: recording_accesses_path(
            source_recording,
            **recording_access_navigation_params(back_url: recording_access_index_back_reference(recording))
          )
        )
      end
    end

    def people_with_access_rows(direct_rows, pending_rows)
      rows = Array(direct_rows).map { |row| row.merge(kind: :grant) }
      Array(pending_rows).each do |invitation|
        rows << {
          kind: :invitation,
          id: invitation.id,
          email: invitation.email,
          role: invitation.role,
          expired: invitation.expired
        }
      end
      rows
    end

    def pending_invitation_person_cell(row)
      parts = [
        content_tag(:span, row[:email], class: "font-medium text-[var(--surface-content-color)]"),
        content_tag(:span, accessible_t("manage.pending_invitation"), class: "text-sm text-[var(--surface-content-color)]")
      ]
      if row[:expired]
        parts << content_tag(:span, accessible_t("manage.expired"), class: "text-sm text-[var(--surface-content-color)]")
      end
      safe_join(parts, " ")
    end

    def pending_invitation_role_cell(row)
      content_tag(:span, access_role_label(row[:role]), class: "text-sm text-[var(--surface-content-color)]")
    end

    def pending_invitation_actions_cell(recording, row)
      resend_form_id = "resend-invitation-form-#{row[:id]}"
      cancel_form_id = "cancel-invitation-form-#{row[:id]}"
      navigation = recording_access_navigation_params

      safe_join(
        [
          invitation_actions_dropdown(resend_form_id, cancel_form_id),
          hidden_method_form(
            resend_form_id,
            resend_recording_access_invitation_path(recording, row[:id], **navigation)
          ),
          hidden_method_form(
            cancel_form_id,
            recording_access_invitation_path(recording, row[:id], **navigation),
            method: :delete
          )
        ]
      )
    end

    def access_actions_cell(recording, row)
      delete_form_id = "remove-access-form-#{row[:id]}"

      dropdown = render FlatPack::Button::Dropdown::Component.new(
        text: "",
        style: :ghost,
        icon: "ellipsis-vertical",
        show_chevron: false,
        trigger_attributes: {
          title: accessible_t("manage.access_actions"),
          aria: { label: accessible_t("manage.access_actions") }
        }
      ) do |dropdown|
        dropdown.menu_item(
          text: accessible_t("manage.edit"),
          href: edit_recording_access_path_with_back_url(recording, row[:id])
        )
        dropdown.menu_item(
          text: accessible_t("manage.remove_access"),
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

    def invitation_actions_dropdown(resend_form_id, cancel_form_id)
      render FlatPack::Button::Dropdown::Component.new(
        text: "",
        style: :ghost,
        icon: "ellipsis-vertical",
        show_chevron: false,
        trigger_attributes: {
          title: accessible_t("manage.invitation_actions"),
          aria: { label: accessible_t("manage.invitation_actions") }
        }
      ) do |dropdown|
        dropdown.menu_item(text: accessible_t("manage.resend"), form: resend_form_id, type: :submit)
        dropdown.menu_item(
          text: accessible_t("manage.cancel_invitation"),
          destructive: true,
          form: cancel_form_id,
          type: :submit
        )
      end
    end

    def hidden_method_form(form_id, url, method: :post)
      form_with(url: url, method: method, local: true, html: { id: form_id, class: "hidden" }) { "" }
    end

    def recording_access_index_back_reference(recording)
      recording_accesses_path(recording, **recording_access_navigation_params(back_url: recording_access_index_back_url))
    end

    def recording_access_navigation_params(back_url: params[:back_url].presence)
      navigation_params = { anchor_url: recording_access_anchor_url }
      navigation_params[:back_url] = safe_local_navigation_url(back_url, fallback: host_root_path) if back_url.present?
      navigation_params
    end

    def host_root_path
      return main_app.root_path if respond_to?(:main_app) && main_app.respond_to?(:root_path)

      "/"
    end

    def access_role_label(role)
      accessible_role_name(role)
    end
  end
end
