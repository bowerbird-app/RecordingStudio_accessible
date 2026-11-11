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
end
