# frozen_string_literal: true

module RecordingStudioAccessible
  module GrantRefusedHelper
    def grant_refused_cta_path
      path = grant_refused_error&.cta_path.presence || flash[:grant_refused_cta_path]
      path.to_s.presence
    end

    def grant_refused_cta_label
      grant_refused_error&.cta_label.presence ||
        flash[:grant_refused_cta_label].presence ||
        accessible_t("flashes.grant_refused_cta")
    end

    def render_grant_refused_cta
      return if grant_refused_cta_path.blank?

      render FlatPack::Button::Component.new(
        text: grant_refused_cta_label,
        href: grant_refused_cta_path,
        style: :primary,
        size: :sm
      )
    end

    private

    def grant_refused_error
      return @grant_refused if defined?(@grant_refused) && @grant_refused

      nil
    end
  end
end
