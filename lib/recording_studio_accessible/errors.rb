# frozen_string_literal: true

module RecordingStudioAccessible
  class Error < StandardError; end

  class AudienceUnauthorized < Error; end
  class AudienceNotAllowed < Error; end
  class AudienceInvalid < Error; end
end
