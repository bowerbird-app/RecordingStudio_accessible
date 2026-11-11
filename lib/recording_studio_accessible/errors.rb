# frozen_string_literal: true

module RecordingStudioAccessible
  class Error < StandardError; end

  class AudienceUnauthorized < Error; end
  class AudienceNotAllowed < Error; end
  class AudienceInvalid < Error; end

  class LastAdminError < Error
    def initialize(message = nil)
      super(message.presence || Copy.t("errors.last_admin"))
    end
  end

  class GrantRefused < Error
    attr_reader :cta_label, :cta_path

    def initialize(message = nil, cta_label: nil, cta_path: nil)
      super(message.presence || Copy.t("errors.grant_refused"))
      @cta_label = cta_label.presence
      @cta_path = cta_path.presence
    end
  end
end
