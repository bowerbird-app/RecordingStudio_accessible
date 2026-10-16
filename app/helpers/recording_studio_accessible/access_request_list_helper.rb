# frozen_string_literal: true

module RecordingStudioAccessible
  module AccessRequestListHelper
    def access_requests_index(recordings:, url: nil)
      render partial: "recording_studio_accessible/access_requests/list",
             locals: access_request_list_locals(recordings, url)
    end

    def access_request_filter_label(status)
      return accessible_t("requests.filter_all") if status == "all"

      accessible_t("requests.statuses.#{status}")
    end

    def access_request_list_subtitle(page)
      return accessible_t("requests.list_subtitle_many") if page.multiple

      label = AccessGrantedMailer.recordable_label_for(page.recording)
      label.presence || accessible_t("requests.list_subtitle")
    end

    def access_request_empty_title(page)
      return accessible_t("requests.list_empty_title") if page.status == "pending"

      accessible_t("requests.list_empty_filtered")
    end

    def access_request_status_badge(request_recording)
      status = request_recording.recordable.status
      render FlatPack::Badge::Component.new(
        text: accessible_t("requests.statuses.#{status}"),
        style: access_request_status_style(status),
        size: :sm
      )
    end

    def access_request_actions_cell(request_recording)
      safe_join([
                  access_request_review_link(request_recording),
                  access_request_cursor_marker(request_recording)
                ])
    end

    def access_request_recording_label(request_recording)
      AccessGrantedMailer.recordable_label_for(request_recording.parent_recording).to_s
    end

    private

    def access_request_list_locals(recordings, url)
      { page: access_request_index_page(recordings), list_url: url.presence || request.path }
    end

    def access_request_index_page(recordings)
      AccessRequestIndex.page(
        recordings: recordings, actor: access_request_index_actor, controller: controller,
        status: params[:status], cursor: params[:cursor]
      )
    end

    def access_request_index_actor
      RecordingStudioAccessible.configuration.current_actor_for(controller: controller)
    end

    def access_request_review_link(request_recording)
      render FlatPack::Link::Component.new(href: access_request_review_path(request_recording)) do
        accessible_t("requests.show_title")
      end
    end

    def access_request_review_path(request_recording)
      access_request_routes.recording_access_request_path(
        request_recording.parent_recording, request_recording
      )
    end

    def access_request_cursor_marker(request_recording)
      tag.span(
        nil, hidden: true,
             data: { pagination_cursor: AccessRequestIndex.cursor_for(request_recording) }
      )
    end
  end
end
