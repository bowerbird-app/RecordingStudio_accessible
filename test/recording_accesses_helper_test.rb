# frozen_string_literal: true

require "test_helper"
require "action_view"
require "ostruct"
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
    class Component
      def initialize(**system_arguments)
        @text = system_arguments[:text]
        @system_arguments = system_arguments
      end
    end
  end
end

class RecordingAccessesHelperTest < Minitest::Test
  class ViewContext
    include ActionView::Helpers::TagHelper
    include ActionView::Helpers::UrlHelper
    include ActionView::Helpers::OutputSafetyHelper
    include RecordingStudioAccessible::Engine.routes.url_helpers
    include RecordingStudioAccessible::RecordingAccessesHelper

    def render(component)
      component_name = component.class.name.to_s

      return "<span>chip</span>".html_safe if component_name == "FlatPack::Chip::Component"
      return "<span>badge</span>".html_safe if component_name == "FlatPack::Badge::Component"

      if component_name == "FlatPack::Button::Component" || component.instance_variable_defined?(:@text)
        text = component.instance_variable_get(:@text)
        return "<button>#{ERB::Util.html_escape(text)}</button>".html_safe
      end

      "<span>rendered</span>".html_safe
    end

    def default_url_options
      {}
    end

    def edit_recording_access_path(recording, access)
      "/recordings/#{recording.to_param}/accesses/#{access}/edit"
    end

    def recording_access_path(recording, access)
      "/recordings/#{recording.to_param}/accesses/#{access}"
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

  def test_access_role_cell_renders_plain_text
    html = ViewContext.new.access_role_cell(direct_role: :admin)

    assert_includes html, ">Admin<"
    refute_includes html, "<span>chip</span>"
    refute_includes html, "<span>badge</span>"
  end

  def test_access_actions_cell_renders_edit_link_and_delete_form_button
    recording = Struct.new(:id, :to_param).new(42, "42")

    html = ViewContext.new.access_actions_cell(recording, id: 7)

    assert_includes html, ">Edit<"
    assert_includes html, "/recordings/42/accesses/7/edit"
    assert_includes html, "/recordings/42/accesses/7"
    assert_includes html, '<form class="inline" method="post" action="/recordings/42/accesses/7">'
    assert_includes html, 'name="_method" value="delete"'
    assert_includes html, 'type="submit" value="Delete"'
    assert_includes html,
                    'class="cursor-pointer text-[var(--danger-text-color,var(--surface-content-color))] underline-offset-2 hover:underline"'
    refute_includes html, ">Actions<"
    refute_includes html, "Edit access"
    refute_includes html, "Delete access"
  end
end
