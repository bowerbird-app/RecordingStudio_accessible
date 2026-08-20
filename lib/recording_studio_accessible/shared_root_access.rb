# frozen_string_literal: true

module RecordingStudioAccessible
  module SharedRootAccess
    GRANT_DENIED_MESSAGE = "Grant access on objects below a shared root, not on the shared root itself."

    module_function

    def target?(recording)
      return false unless defined?(::RecordingStudio)
      return false if recording.blank?

      return true if RecordingStudio.shared_root?(recording)
      return false unless RecordingStudio.respond_to?(:shared_root_type?)
      return false unless recording.respond_to?(:recordable_type)

      RecordingStudio.shared_root_type?(recording.recordable_type)
    rescue StandardError
      false
    end
  end
end
