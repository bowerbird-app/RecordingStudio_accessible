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
end
