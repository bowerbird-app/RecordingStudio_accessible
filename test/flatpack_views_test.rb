# frozen_string_literal: true

require "test_helper"

class FlatpackViewsTest < Minitest::Test
  def test_access_request_modals_do_not_use_inline_javascript
    views = RecordingStudioAccessible::Engine.root.join("app/views/recording_studio_accessible/access_requests")

    %w[_modal.html.erb _review_modal.html.erb].each do |name|
      source = File.read(views.join(name))

      refute_includes source, "javascript_tag", "#{name} still has inline JavaScript"
      refute_includes source, "<script", "#{name} still has a script tag"
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
