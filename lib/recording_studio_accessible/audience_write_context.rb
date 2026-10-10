# frozen_string_literal: true

module RecordingStudioAccessible
  module AudienceWriteContext
    THREAD_KEY = :recording_studio_accessible_audience_write_allowed

    class << self
      def allow
        previous = Thread.current[THREAD_KEY]
        Thread.current[THREAD_KEY] = true
        yield
      ensure
        Thread.current[THREAD_KEY] = previous
      end

      def allowed?
        Thread.current[THREAD_KEY] == true
      end
    end
  end
end
