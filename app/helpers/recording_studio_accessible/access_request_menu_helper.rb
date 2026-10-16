# frozen_string_literal: true

require_relative "access_request_menu_forms"

module RecordingStudioAccessible
  module AccessRequestMenuHelper
    include AccessRequestMenuForms

    def access_request_actions_cell(request_recording)
      safe_join([
                  access_request_actions_menu(request_recording),
                  access_request_menu_forms(request_recording),
                  access_request_cursor_marker(request_recording)
                ])
    end

    private

    def access_request_actions_menu(request_recording)
      render FlatPack::Button::Dropdown::Component.new(**access_request_menu_trigger) do |dropdown|
        access_request_fill_menu(dropdown, request_recording)
      end
    end

    def access_request_menu_trigger
      {
        text: "", style: :ghost, size: :sm, icon: "ellipsis-vertical", show_chevron: false,
        placement: :bottom_left,
        trigger_attributes: {
          title: accessible_t("requests.actions_label"),
          aria: { label: accessible_t("requests.actions_label") }
        }
      }
    end

    def access_request_fill_menu(dropdown, request_recording)
      dropdown.menu_item(text: accessible_t("requests.menu.view"), href: access_request_review_path(request_recording))
      dropdown.menu_divider
      access_request_status_items(dropdown, request_recording)
    end

    def access_request_status_items(dropdown, request_recording)
      AccessRequestTransitions.targets_for(request_recording.recordable.status).each do |status|
        access_request_status_item(dropdown, request_recording, status)
      end
    end

    def access_request_status_item(dropdown, request_recording, status)
      return access_request_approve_items(dropdown, request_recording) if status == "approved"

      dropdown.menu_item(**access_request_submit_item(request_recording, status))
    end

    def access_request_approve_items(dropdown, request_recording)
      access_request_role_options(request_recording).each do |role|
        dropdown.menu_item(**access_request_submit_item(request_recording, "approved", role))
      end
    end

    def access_request_submit_item(request_recording, status, role = nil)
      item = {
        text: access_request_menu_label(status, role),
        form: access_request_form_id(request_recording, status, role),
        type: :submit
      }
      item[:destructive] = true if status == "denied"
      item
    end

    def access_request_menu_label(status, role)
      return accessible_t("requests.menu.approve_as", role: accessible_role_name(role)) if role

      accessible_t("requests.menu.#{status}")
    end
  end
end
