# frozen_string_literal: true

require "test_helper"
require "json"
require "digest"

# Proves Accessible's query-only Trashable load does not pull engine side effects
# into the dummy host (importmap pin/modulepreload, :trashable capability,
# lifecycle trash!/restore!/purge!, CopyHelper, trash.* metrics).
class TrashableQuerySurfaceTest < ActiveSupport::TestCase
  test "no Trashable engine constant or CopyHelper" do
    refute defined?(RecordingStudioTrashable::Engine)
    refute defined?(RecordingStudioTrashable::CopyHelper)
    assert defined?(RecordingStudioTrashable)
    assert_equal "0.10.0", RecordingStudioTrashable::VERSION
  end

  test "does not register :trashable capability" do
    names = RecordingStudio.registered_capabilities.map(&:to_s)

    refute_includes names, "trashable"
    assert_nil RecordingStudio.capability_options(:trashable)
  end

  test "Recording does not gain trash! restore! purge! lifecycle methods" do
    recording = RecordingStudio::Recording.unscoped.first ||
                create_root_recording(Workspace.create!(name: "Surface workspace"))

    refute_respond_to recording, :recording_studio_trashable_trash!
    refute_respond_to recording, :recording_studio_trashable_restore!
    refute_respond_to recording, :recording_studio_trashable_purge!
  end

  test "javascript_importmap_tags has no trashable live_search pin or modulepreload" do
    helpers = Class.new do
      include ActionView::Helpers::TagHelper
      include ActionView::Helpers::AssetTagHelper
      include ActionView::Helpers::AssetUrlHelper
      include Importmap::ImportmapTagsHelper if defined?(Importmap::ImportmapTagsHelper)

      def controller = nil
      def request = ActionDispatch::Request.empty
      def config = Rails.application.config.action_controller
    end.new

    html = helpers.javascript_importmap_tags
    imports = Rails.application.importmap.to_json(resolver: ActionController::Base.helpers)
    parsed = JSON.parse(imports)
    pin_keys = (parsed["imports"] || {}).keys

    refute_includes pin_keys, "controllers/recording_studio_trashable/live_search_controller"
    refute_match(/recording_studio_trashable/, html)
    refute_match(/live_search_controller/, html)
    refute_match(%r{modulepreload[^>]*trashable}i, html)

    paths = Rails.application.config.importmap.paths.map(&:to_s)
    refute(paths.any? { |path| path.include?("RecordingStudio_trashable") && path.end_with?("importmap.rb") })
  end

  test "no trash.* metrics resource is registered by Accessible boot" do
    skip "RecordingStudioMetrics not loaded" unless defined?(RecordingStudioMetrics)

    registry = RecordingStudioMetrics.registry
    names = case registry
            when Hash then registry.keys.map(&:to_s)
            when Array then registry.map { |entry| entry.respond_to?(:name) ? entry.name.to_s : entry.to_s }
            else
              Array(registry).map(&:to_s)
            end

    refute_includes names, "trash"
    refute(names.any? { |name| name.start_with?("trash.") })

    if RecordingStudioMetrics.respond_to?(:for_resource)
      trash_metrics = RecordingStudioMetrics.for_resource(:trash)
      assert_empty Array(trash_metrics)
    end
  end
end
