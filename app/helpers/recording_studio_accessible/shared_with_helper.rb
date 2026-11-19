# frozen_string_literal: true

module RecordingStudioAccessible
  module SharedWithHelper
    def shared_with_item(item)
      title = shared_with_title(item)
      detail = shared_with_detail(item)
      render FlatPack::List::Item.new(align: :start) do |row|
        row.with_title { title }
        row.with_subtitle { detail }
      end
    end

    private

    def shared_with_title(item)
      safe_join([
                  shared_with_link(item),
                  tag.span(nil, hidden: true, data: { pagination_cursor: item.cursor })
                ])
    end

    def shared_with_link(item)
      render(FlatPack::Link::Component.new(
               href: item.url,
               class: "text-[var(--color-primary)] underline break-words"
             )) { item.title }
    end

    def shared_with_detail(item)
      render FlatPack::Text::Component.new(
        text: item.workspace.to_s,
        size: :sm,
        style: :muted,
        as: :p,
        class: "fp-list-item-subtitle mt-0.5 break-words"
      )
    end
  end
end
