# frozen_string_literal: true

require_relative "access_request_menu_helper"

module RecordingStudioAccessible
  module AccessRequestListHelper
    include AccessRequestMenuHelper

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

    def access_request_note_cell(request_recording)
      message = request_recording.recordable.message.to_s
      tag.span(message, class: "block max-w-sm truncate", title: message)
    end

    def access_request_recording_label(request_recording)
      label = AccessGrantedMailer.recordable_label_for(request_recording.parent_recording).to_s
      href = access_request_recording_href(request_recording)
      return label if href.blank?

      render(FlatPack::Link::Component.new(href: href)) { label }
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

    def access_request_recording_href(request_recording)
      recordable = request_recording.parent_recording&.recordable
      return if recordable.blank? || !respond_to?(:main_app)

      main_app.polymorphic_path(recordable)
    rescue ActionController::UrlGenerationError, NoMethodError, ArgumentError
      nil
    end
  end
end
