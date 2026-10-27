# frozen_string_literal: true

require "test_helper"

class FlatpackViewsTest < Minitest::Test
  def test_access_request_modals_hide_open_dialogs_before_turbo_caches
    views = RecordingStudioAccessible::Engine.root.join("app/views/recording_studio_accessible/access_requests")
    hide_on_cache = File.read(views.join("_hide_on_cache.html.erb"))

    assert_includes hide_on_cache, "javascript_tag"
    assert_includes hide_on_cache, "turbo:before-cache"
    assert_includes hide_on_cache, "[data-controller='flat-pack--modal'][id^='access-request-']"

    %w[_modal.html.erb _review_modal.html.erb].each do |name|
      source = File.read(views.join(name))

      assert_includes source, "hide_on_cache", "#{name} must render the shared before-cache script"
      refute_includes source, "javascript_tag", "#{name} must not duplicate the shared script"
      assert_includes source, "FlatPack::Modal::Component", "#{name} must render the FlatPack modal"
    end
  end

  def test_access_request_heading_uses_page_title
    source = File.read(
      RecordingStudioAccessible::Engine.root.join(
        "app/views/recording_studio_accessible/access_requests/_heading.html.erb"
      )
    )

    assert_includes source, "FlatPack::PageTitle::Component"
    refute_includes source, "<h1 class="
  end

  def test_access_request_show_uses_quote
    source = File.read(
      RecordingStudioAccessible::Engine.root.join(
        "app/views/recording_studio_accessible/access_requests/show.html.erb"
      )
    )

    assert_includes source, "FlatPack::Quote::Component"
    refute_includes source, '"<%= request_record.message %>"'
  end
end
