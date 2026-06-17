# frozen_string_literal: true

require "test_helper"
require "action_view"
require "ostruct"
require "cgi"
require "recording_studio_accessible/engine"
require "recording_studio_accessible"
require_relative "../app/helpers/recording_studio_accessible/recording_accesses_helper"

module FlatPack
  module Chip
    class Component
      def initialize(**); end
    end
  end

  module Badge
    class Component
      def initialize(**); end
    end
  end

  module Button
    module Dropdown
      class Component
        attr_reader :menu

        def initialize(**)
          @menu = []
        end

        def menu_item(text:, href: nil, **system_arguments)
          item = Object.new
          item.instance_variable_set(:@text, text)
          item.instance_variable_set(:@href, href)
          item.instance_variable_set(:@system_arguments, system_arguments)
          @menu << item
          item
        end
      end
    end

    class Component
      unless private_instance_methods(false).include?(:initialize)
        def initialize(**system_arguments)
          @text = system_arguments[:text]
          @system_arguments = system_arguments
        end
      end
    end
  end
end

class RecordingAccessesHelperTest < Minitest::Test
  class ViewContext
    include ActionView::Helpers::TagHelper
    include ActionView::Helpers::UrlHelper
    include ActionView::Helpers::FormHelper
    include ActionView::Helpers::OutputSafetyHelper
    include RecordingStudioAccessible::Engine.routes.url_helpers
    include RecordingStudioAccessible::RecordingAccessesHelper

    attr_writer :params

    def render(component, &block)
      component_name = component.class.name.to_s

      return "<span>chip</span>".html_safe if component_name == "FlatPack::Chip::Component"
      return "<span>badge</span>".html_safe if component_name == "FlatPack::Badge::Component"

      if component_name == "FlatPack::Button::Dropdown::Component"
        block&.call(component)

        items_html = component.menu.map do |item|
          text = ERB::Util.html_escape(item.instance_variable_get(:@text).to_s)
          href = item.instance_variable_get(:@href)
          system_arguments = item.instance_variable_get(:@system_arguments).to_h

          if href.present?
            escaped_href = ERB::Util.html_escape(href.to_s)
            %(<a href="#{escaped_href}">#{text}</a>)
          else
            form = system_arguments[:form] || system_arguments["form"]
            type = system_arguments[:type] || system_arguments["type"] || "button"
            form_attribute = form ? %( form="#{ERB::Util.html_escape(form.to_s)}") : ""
            %(<button type="#{ERB::Util.html_escape(type.to_s)}"#{form_attribute}>#{text}</button>)
          end
        end.join

        return %(<div data-controller="flat-pack--button-dropdown">#{items_html}</div>).html_safe
      end

      if component_name == "FlatPack::Button::Component" || component.instance_variable_defined?(:@text)
        text = component.instance_variable_get(:@text)
        return "<button>#{ERB::Util.html_escape(text)}</button>".html_safe
      end

      "<span>rendered</span>".html_safe
    end

    def default_url_options
      {}
    end

    def params
      @params ||= {}
    end

    def main_app
      self
    end

    def root_path
      "/"
    end

    def edit_recording_access_path(recording, access, options = {})
      append_query_string("/recordings/#{recording.to_param}/accesses/#{access}/edit", options)
    end

    def recording_access_path(recording, access, options = {})
      append_query_string("/recordings/#{recording.to_param}/accesses/#{access}", options)
    end

    def recording_accesses_path(recording, options = {})
      append_query_string("/recordings/#{recording.to_param}/accesses", options)
    end

    def new_recording_access_path(recording, options = {})
      append_query_string("/recordings/#{recording.to_param}/accesses/new", options)
    end

    private

    def append_query_string(path, options)
      query = options.compact.map do |key, value|
        "#{CGI.escape(key.to_s)}=#{CGI.escape(value.to_s)}"
      end.join("&")

      query.empty? ? path : "#{path}?#{query}"
    end
  end

  class ViewContextWithoutRoot < ViewContext
    def main_app
      Object.new
    end
  end

  def test_access_person_cell_renders_only_the_actor_label
    html = ViewContext.new.access_person_cell(actor_label: "Ada Lovelace", actor_type: "User")

    assert_includes html, "Ada Lovelace"
    refute_includes html, "<span>chip</span>"
  end

  def test_access_actor_type_cell_renders_plain_text
    html = ViewContext.new.access_actor_type_cell(actor_type: "User")

    assert_includes html, ">User<"
    refute_includes html, "<span>chip</span>"
    refute_includes html, "<span>badge</span>"
  end

  def test_show_access_actor_type_column_returns_false_for_single_actor_type
    visible = ViewContext.new.show_access_actor_type_column?(
      [{ actor_type: "User" }, { actor_type: "User" }],
      [{ actor_type: "User" }]
    )

    refute visible
  end

  def test_show_access_actor_type_column_returns_true_for_multiple_actor_types
    visible = ViewContext.new.show_access_actor_type_column?(
      [{ actor_type: "User" }],
      [{ actor_type: "ServiceAccount" }]
    )

    assert visible
  end

  def test_access_role_cell_renders_plain_text
    html = ViewContext.new.access_role_cell(direct_role: :admin)

    assert_includes html, ">Admin<"
    refute_includes html, "<span>chip</span>"
    refute_includes html, "<span>badge</span>"
  end

  def test_access_actions_cell_renders_dropdown_with_edit_and_remove_access_menu_items
    recording = Struct.new(:id, :to_param).new(42, "42")
    view_context = ViewContext.new
    view_context.params = { back_url: "/users/7" }
    expected_index_path = "/recordings/42/accesses?anchor_url=%2Fusers%2F7&back_url=%2Fusers%2F7"
    expected_edit_path = "/recordings/42/accesses/7/edit?anchor_url=%2Fusers%2F7&back_url=#{CGI.escape(expected_index_path)}"
    expected_delete_path = "/recordings/42/accesses/7?anchor_url=%2Fusers%2F7&back_url=%2Fusers%2F7"
    expected_edit_href = CGI.escapeHTML(expected_edit_path)
    expected_delete_action = CGI.escapeHTML(expected_delete_path)

    html = view_context.access_actions_cell(recording, id: 7)

    assert_includes html, 'data-controller="flat-pack--button-dropdown"'
    assert_includes html, ">Edit<"
    assert_includes html, expected_edit_href
    assert_includes html, ">Remove access<"
    assert_includes html, '<button type="submit" form="remove-access-form-7">Remove access</button>'
    assert_includes html, %(<form id="remove-access-form-7" class="hidden" action="#{expected_delete_action}" accept-charset="UTF-8" method="post">)
    assert_includes html, 'name="_method" value="delete"'
    refute_includes html, "Edit access"
    refute_includes html, ">Delete<"
  end

  def test_inherited_access_actions_cell_renders_manage_access_menu_item_for_source_recording
    recording = Struct.new(:id, :to_param).new(42, "42")
    source_recording = Struct.new(:id, :to_param).new(11, "11")
    view_context = ViewContext.new
    view_context.params = { back_url: "/users/7" }
    expected_index_path = "/recordings/42/accesses?anchor_url=%2Fusers%2F7&back_url=%2Fusers%2F7"
    expected_manage_path = "/recordings/11/accesses?anchor_url=%2Fusers%2F7&back_url=#{CGI.escape(expected_index_path)}"

    html = view_context.inherited_access_actions_cell(recording, source_recording: source_recording)

    assert_includes html, 'data-controller="flat-pack--button-dropdown"'
    assert_includes html, ">Manage access<"
    assert_includes html, CGI.escapeHTML(expected_manage_path)
  end

  def test_new_recording_access_path_with_back_url_escapes_nested_back_url_once
    recording = Struct.new(:id, :to_param).new(42, "42")
    expected_index_path = "/recordings/42/accesses?anchor_url=%2F&back_url=%2F"

    path = ViewContext.new.new_recording_access_path_with_back_url(recording)

    assert_equal "/recordings/42/accesses/new?anchor_url=%2F&back_url=#{CGI.escape(expected_index_path)}", path
  end

  def test_recording_access_index_back_url_falls_back_without_host_root_path
    assert_equal "/", ViewContextWithoutRoot.new.recording_access_index_back_url
  end

  def test_recording_access_anchor_url_falls_back_without_host_root_path
    assert_equal "/", ViewContextWithoutRoot.new.recording_access_anchor_url
  end

  def test_recording_access_index_back_url_prefers_explicit_param_without_host_root_path
    view_context = ViewContextWithoutRoot.new
    view_context.params = { back_url: "/recordings" }

    assert_equal "/recordings", view_context.recording_access_index_back_url
  end
end
