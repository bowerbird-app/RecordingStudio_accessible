# frozen_string_literal: true

require "test_helper"
require "action_view"
require "cgi"
require "ostruct"
require "recording_studio_accessible/engine"
require "recording_studio_accessible"
require_relative "../app/helpers/recording_studio_accessible/avatars_helper"

module FlatPack
  module AvatarGroup
    class Component
      attr_reader :system_arguments

      def initialize(**system_arguments)
        @system_arguments = system_arguments
      end
    end
  end

  module Tooltip
    class Component
      attr_reader :system_arguments

      def initialize(**system_arguments)
        @system_arguments = system_arguments
      end
    end
  end

  module Button
    class Component
      attr_reader :system_arguments

      def initialize(**system_arguments)
        @text = system_arguments[:text]
        @system_arguments = system_arguments
      end
    end
  end
end

class AvatarsHelperTest < Minitest::Test
  AccessGrant = Struct.new(:actor)
  AccessRecording = Struct.new(:recordable)
  Actor = Struct.new(:name, :avatar_url)
  Recording = Struct.new(:id, :to_param)

  class ViewContext
    include ActionView::Helpers::TagHelper
    include ActionView::Helpers::OutputSafetyHelper
    include ActionView::Helpers::CaptureHelper
    include RecordingStudioAccessible::AvatarsHelper

    def render(component, &)
      component_name = component.class.name.to_s

      case component_name
      when "FlatPack::AvatarGroup::Component"
        render_avatar_group(component)
      when "FlatPack::Tooltip::Component"
        render_tooltip(component, &)
      when "FlatPack::Button::Component"
        render_button(component)
      else
        "<span>rendered</span>".html_safe
      end
    end

    def recording_accesses_path(recording)
      "/recordings/#{recording.to_param}/accesses"
    end

    def current_user
      :manager
    end

    private

    def render_avatar_group(component)
      arguments = component.system_arguments
      item_markup = arguments.fetch(:items).map do |item|
        %(<span data-avatar-name="#{ERB::Util.html_escape(item[:name])}" data-avatar-src="#{ERB::Util.html_escape(item[:src])}"></span>)
      end.join

      %(<avatar-group data-max="#{arguments[:max]}" data-size="#{arguments[:size]}" data-overflow-href="#{ERB::Util.html_escape(arguments[:overflow_href])}">#{item_markup}</avatar-group>).html_safe
    end

    def render_tooltip(component, &block)
      arguments = component.system_arguments
      content = block ? block.call : ""

      %(<tooltip data-text="#{ERB::Util.html_escape(arguments[:text])}" data-placement="#{arguments[:placement]}">#{content}</tooltip>).html_safe
    end

    def render_button(component)
      arguments = component.system_arguments

      %(<button data-style="#{arguments[:style]}" data-size="#{arguments[:size]}" data-url="#{ERB::Util.html_escape(arguments[:url])}">#{ERB::Util.html_escape(arguments[:text])}</button>).html_safe
    end
  end

  def setup
    @original_configuration = RecordingStudioAccessible.instance_variable_get(:@configuration)
    RecordingStudioAccessible.instance_variable_set(:@configuration, RecordingStudioAccessible::Configuration.new)
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { true }
  end

  def teardown
    RecordingStudioAccessible.instance_variable_set(:@configuration, @original_configuration)
  end

  def test_renders_tooltip_wrapped_avatar_group_from_access_holders
    actor = Actor.new("Ada Lovelace", "https://example.com/ada.png")
    recording = Recording.new(42, "42")
    RecordingStudioAccessible.configuration.avatar_resolver = lambda do |access_holder|
      { name: access_holder.name, image_url: access_holder.avatar_url }
    end

    html = with_access_recordings(recording, [access_recording_for(actor)]) do
      ViewContext.new.recording_studio_accessible_avatars(recording)
    end

    assert_includes html, '<tooltip data-text="Manage access" data-placement="top">'
    assert_includes html, '<avatar-group data-max="5" data-size="sm" data-overflow-href="/recordings/42/accesses">'
    assert_includes html, 'data-avatar-name="Ada Lovelace"'
    assert_includes html, 'data-avatar-src="https://example.com/ada.png"'
    refute_includes html, "+ Access"
  end

  def test_fetches_access_recordings_for_the_requested_recording
    requested_recording = Recording.new(42, "42")
    other_recording = Recording.new(7, "7")
    requested_actor = Actor.new("Requested", nil)
    RecordingStudioAccessible.configuration.avatar_resolver = ->(access_holder) { { name: access_holder.name } }

    html = with_access_recordings(requested_recording, [access_recording_for(requested_actor)]) do
      ViewContext.new.recording_studio_accessible_avatars(requested_recording)
    end

    assert_includes html, 'data-avatar-name="Requested"'
    assert_raises Minitest::Assertion do
      with_access_recordings(requested_recording, []) do
        ViewContext.new.recording_studio_accessible_avatars(other_recording)
      end
    end
  end

  def test_renders_access_button_when_no_access_holders_exist
    recording = Recording.new(42, "42")

    html = with_access_recordings(recording, []) do
      ViewContext.new.recording_studio_accessible_avatars(recording)
    end

    assert_includes html, ">+ Access</button>"
    assert_includes html, 'data-style="default"'
    assert_includes html, 'data-url="/recordings/42/accesses"'
    refute_includes html, "avatar-group"
  end

  def test_renders_access_button_when_resolver_returns_nil
    actor = Actor.new("Unrenderable", nil)
    recording = Recording.new(42, "42")
    RecordingStudioAccessible.configuration.avatar_resolver = ->(_access_holder) {}

    html = with_access_recordings(recording, [access_recording_for(actor)]) do
      ViewContext.new.recording_studio_accessible_avatars(recording)
    end

    assert_includes html, ">+ Access</button>"
    refute_includes html, "avatar-group"
  end

  def test_custom_button_style_is_passed_to_flatpack_button
    recording = Recording.new(42, "42")

    html = with_access_recordings(recording, []) do
      ViewContext.new.recording_studio_accessible_avatars(recording, button_style: :primary)
    end

    assert_includes html, 'data-style="primary"'
  end

  def test_avatar_names_are_escaped_by_component_rendering
    actor = Actor.new("<script>alert('x')</script>", nil)
    recording = Recording.new(42, "42")
    RecordingStudioAccessible.configuration.avatar_resolver = ->(access_holder) { { name: access_holder.name } }

    html = with_access_recordings(recording, [access_recording_for(actor)]) do
      ViewContext.new.recording_studio_accessible_avatars(recording)
    end

    assert_includes html, CGI.escapeHTML(actor.name)
    refute_includes html, actor.name
  end

  def test_renders_nothing_when_current_actor_cannot_manage_access
    actor = Actor.new("Ada Lovelace", nil)
    recording = Recording.new(42, "42")
    RecordingStudioAccessible.configuration.access_management_authorizer = ->(**) { false }
    RecordingStudioAccessible.configuration.avatar_resolver = ->(access_holder) { { name: access_holder.name } }

    html = with_access_recordings(recording, [access_recording_for(actor)], expected_calls: []) do
      ViewContext.new.recording_studio_accessible_avatars(recording)
    end

    assert_equal "", html
  end

  private

  def access_recording_for(actor)
    AccessRecording.new(AccessGrant.new(actor))
  end

  def with_access_recordings(expected_recording, access_recordings, expected_calls: [expected_recording], &block)
    calls = []
    resolver = lambda do |recording|
      calls << recording
      assert_same expected_recording, recording

      access_recordings
    end

    RecordingStudioAccessible.stub(:access_recordings_for, resolver) do
      block.call
    end
  ensure
    assert_equal expected_calls, calls
  end
end
