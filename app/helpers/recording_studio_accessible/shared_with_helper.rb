# frozen_string_literal: true

module RecordingStudioAccessible
  module SharedWithHelper
    def shared_with_name(item)
      safe_join([
                  render(FlatPack::Link::Component.new(href: item.url)) { item.title },
                  tag.span(nil, hidden: true, data: { pagination_cursor: item.cursor })
                ])
    end
  end
end
