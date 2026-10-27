# frozen_string_literal: true

require "test_helper"

class CompanionHackCleanupTest < ActiveSupport::TestCase
  test "dummy does not prepend FlatPack PageNav or Card shims" do
    refute_includes FlatPack::PageNav::Component.ancestors.map(&:name), "DummyPageNavClose"
    refute_includes FlatPack::Card::Component.ancestors.map(&:name), "DummyCardWithoutStyle"
    refute_path_exists Rails.root.join("config/initializers/page_nav_close.rb")
  end

  test "dummy does not stub UsesDefaultLayout for old Trashable" do
    refute_path_exists Rails.root.join("config/initializers/recording_studio_default_layout.rb")
    refute defined?(RecordingStudio::UsesDefaultLayout)
  end

  test "dummy does not define a FlatPack Tree stand-in" do
    refute_path_exists Rails.root.join("app/components/flat_pack/tree/component.rb")
  end

  test "dummy does not ship the leftover hello Stimulus controller" do
    refute_path_exists Rails.root.join("app/javascript/controllers/hello_controller.js")
  end
end
