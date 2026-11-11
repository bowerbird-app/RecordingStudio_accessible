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
    attr_reader :redirect_to

    def initialize(message = nil, redirect_to: nil)
      super(message.presence || Copy.t("errors.grant_refused"))
      @redirect_to = redirect_to.presence
    end
  end
end
